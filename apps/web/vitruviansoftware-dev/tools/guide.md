---
layout: tools
title: "Writing a tool for Vitruvian"
description: "From nothing to a working tool in ten minutes, then the manifest, every message, the limits, and how to find out why a tool does not work."
permalink: /tools/guide/
source: packages/vitruvian-sdk/docs/writing-a-tool.md
---
{%- comment -%}
  Written by tools/sync-site-tools/sync.py from packages/vitruvian-sdk.
  Do not edit it: change the source, then run
    bazel run //tools/sync-site-tools:sync
{%- endcomment -%}
{% raw %}
This is the guide for someone who wants to write a tool. It covers what a
tool is, how to write one in ten minutes, the manifest, every message, the
limits, how to add a tool to the app, and how to find out why one does not
work.

The exact statement of the protocol is [`protocol/`](/tools/protocol/).
Where this page and the schemas there disagree, the schemas are right.

## What a tool is

A tool is a folder with two things in it: a file called `vitruvian-tool.json`
that says what the tool is, and a program. The Vitruvian app starts the
program when it is needed and talks to it in JSON, one message per line, over
the program's standard input and output. A tool adds commands to the app: to
the command bar, the radial menu, the Quick panel, and as shortcuts. It can be
written in any language.

**A tool can do anything Vitruvian can.** The app starts it as an ordinary
program. It runs as the person, with every permission Vitruvian has: if
Vitruvian may read the screen or control other apps, so may the tool, with no
prompt of its own. It can read the person's files and use the network. The app
does not limit or check what it does.

**The person agrees once.** They add a tool from a folder, by hand, after
reading one sheet that says exactly this. Nothing asks again, for any
command or any service. That is why there is no store of tools.

## Your first tool, in ten minutes

You need a Mac. Install the `vitruvian-tool` command with Homebrew, which
builds it from source on your Mac:

```sh
brew install VitruvianSoftware/tap/vitruvian-tool
vitruvian-tool --version
```

Without Homebrew, download `vitruvian-tool-<version>-macos.tar.gz` and the
`.sha256` file beside it from the
[releases](https://github.com/VitruvianSoftware/vitruvian-sdk/releases), and
unpack it in the same folder:

```sh
shasum -a 256 -c vitruvian-tool-*-macos.tar.gz.sha256
tar -xzf vitruvian-tool-*-macos.tar.gz
xattr -d com.apple.quarantine vitruvian-tool
```

The last line is there because the program is signed ad hoc, not with an
Apple Developer ID. macOS marks a file a browser downloaded, and will not
open a program with that mark unless a Developer ID signed it. The line takes
the mark off that one file. Run it only when the checksum matched. Homebrew
needs none of this: what it builds on your Mac carries no mark.

In a checkout of the vitruvian-core repository, from its root, the same
command is:

```sh
bazel run --config=macos-app //packages/vitruvian-sdk:vitruvian-tool --
```

### In Python, with nothing

```sh
vitruvian-tool init ~/my-tool --id com.you.my-tool --name "My tool" --publisher "You"
vitruvian-tool validate ~/my-tool
vitruvian-tool run ~/my-tool
```

`init` writes two files: the manifest, and `bin/tool.py`, a copy of the sample
in [`samples/hello-python`](/tools/examples/python/). It writes only in the
folder you name, and only when that folder is not there yet or is empty.
`validate` reads the folder the way the app will. `run` starts the tool and
plays the app's side in your terminal: type `hello` and Return, then `quit`.

`run` is not the app. When it starts a tool it prints one line, after the
word `note`, that says where it differs:

```text
This is not the app. Every service the manifest lists is granted, and nothing real is done. There is no idle stop, no restart after a crash and no flood count.
```

The first line of `bin/tool.py` is `#!/usr/bin/env python3`. In a terminal
that finds your Python. The app looks in fewer places: see
[What a tool must not assume](#what-a-tool-must-not-assume) before you add
the tool to the app.

The whole of the protocol, for a tool that asks the app for something, is this
function and the loop that calls it:

```python
def ask(method, params):
    """Asks the app for something, and waits for its answer."""
    global asked
    asked += 1
    send({"jsonrpc": "2.0", "id": asked, "method": method, "params": params})
    while True:
        message = read()
        if message is None or message.get("method") == "shutdown":
            sys.exit(0)
        if "method" not in message and message.get("id") == asked:
            if "error" in message:
                raise Refused(message["error"])
            return message["result"]
        kept.append(message)
```

A command is then a few lines:

```python
def copy_time():
    now = datetime.datetime.now().strftime("%H:%M:%S")
    ask("clipboard/writeText", {"text": now})
    ask("notify/hud", {"icon": "clock", "message": "Copied " + now})
```

To add a command: write its function, add it to `COMMANDS`, and add it to
`contributes.commands` in the manifest. If it calls a new service of the app,
add the service to `uses`.

### In Swift, with the kit

```sh
vitruvian-tool init ~/my-swift-tool --id com.you.my-swift-tool --name "My Swift tool" --publisher "You" --template swift
~/my-swift-tool/build.sh
vitruvian-tool validate ~/my-swift-tool/tool
vitruvian-tool run ~/my-swift-tool/tool
```

This writes a Swift package and, beside it, `tool/`: the folder you add to the
app. `build.sh` builds the package and copies the program into `tool/bin/`.
The package depends on the published SDK,
`https://github.com/VitruvianSoftware/vitruvian-sdk`, from the version that
`vitruvian-tool --version` prints, and its first build fetches it. To build
against a checkout of the SDK instead, add `--sdk` and the checkout's folder.

The whole tool is one file:

```swift
import VitruvianToolKit

let tool = Tool(version: "0.1.0")

tool.command("hello") { app in
    try app.showMessage("Hello from a Swift tool", icon: "hand.wave")
}

tool.command("count") { app in
    // The step is saved as text. The options are how the app draws the
    // setting, not a rule on what is saved: an app before 3.48 draws a text
    // field, so anything may be there. What is no number counts as one.
    let step = Double(try app.value("step").stringValue ?? "") ?? 1
    let next = (try app.value("count").numberValue ?? 0) + step
    try app.setValue(.number(next), for: "count")
    try app.showMessage("Counted to \(Int(next))", icon: "number")
}

tool.run()
```

What the kit gives a handler:

| Call on `app` | Message | In `uses` |
|---|---|---|
| `showMessage(_:icon:)` | `notify/hud` | `notify` |
| `beep()` | `notify/beep` | `notify` |
| `open(_:)` | `open/url` | `open` |
| `clipboardText()` | `clipboard/readText` | `clipboard.read` |
| `setClipboardText(_:)` | `clipboard/writeText` | `clipboard.write` |
| `paste(_:)` | `keystrokes/paste` | `keystrokes` |
| `pressMenuItem(_:)` | `keystrokes/pressMenuItem` | `keystrokes` |
| `endProcess(pid:name:force:)` | `processes/terminate` | `processes` |
| `value(_:)`, `setValue(_:for:)` | `storage/get`, `storage/set` | `storage` |
| `setRunnable(_:)` | `commands/state` | |
| `log(_:)` | `log` | |
| `language`, `dataFolder` | what `initialize` said | |
| `render(_:)`, on a panel | `ui/render` | |
| `badge(count:dot:)`, on a panel | `ui/badge` | `notify` |
| `status(_:text:icon:)` | `ui/status` | |
| `supports(_:)` | what `initialize` said the app has | |

Three rules of the kit:

- **A call can be refused.** It then throws the failure the app answered
  with, an `RPCErrorObject`. If your handler lets it through, the command is
  answered as refused. Throw `CommandRefused("why")` to refuse a command
  yourself.
- **The kit works on one thread**, the one that calls `run()`. A handler runs
  on it, and a call to the app waits on it for the answer, ten seconds at
  most. Do not use `tool` or `app` from another thread.
- **Never `print`.** Standard output is the link. Write to standard error,
  or call `app.log`.

To hear that the person changed a preference, set `tool.onPreferencesChanged`
before `run()`. It is handed the id and the new value of each preference that
changed. A tool that reads its preferences each time a command runs, as the
sample above does, needs no such handler.

The same goes for the app's language. `app.language` is always the current
one: the kit follows `language/changed` by itself. Set
`tool.onLanguageChanged` before `run()` only when your tool must do
something at that moment.

A tool that watches something, a service it polls or a folder it reads,
sets a timer before `run()`: `tool.every(seconds: 30) { app in … }`. The
handler runs on the kit's one thread, between messages: never while a
command or a panel's handler is running or waiting for the app, and not
before the app has said hello, so it may call the app like any handler. A
handler that runs late runs once, not again to catch up; an error it
throws goes to the tool's log and the timer goes on. Ask for a few seconds
at least.

A tool with a thread of its own, one that shows a window or waits on a
child process, hands work to the kit's thread with
`tool.waker.later { app in … }`, from any thread. The work runs on the
kit's thread as soon as it is between messages, after the hello, and may
call the app like any handler; an error it throws goes to the tool's log.
Nothing else of a `Tool` may be used from another thread.

### In TypeScript, with the kit

```sh
vitruvian-tool init ~/my-ts-tool --id com.you.my-ts-tool --name "My TypeScript tool" --publisher "You" --template typescript
cd ~/my-ts-tool && npm install
vitruvian-tool validate ~/my-ts-tool
vitruvian-tool run ~/my-ts-tool
```

This writes the manifest, `bin/tool.mjs`, `bin/tool` and a `package.json` that
depends on [`@vitruviansoftware/tool-kit`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/kits/typescript) at the version
of this SDK. `npm install` puts the kit in `node_modules/`, inside the tool's
folder, which is where it must be: the app runs the folder as it is, and
`node_modules/` goes with it. You need Node 20 or later.

There is no build step. The program is JavaScript that Node runs as it is,
and its first line, `// @ts-check`, has an editor check it against the kit's
types. The whole tool is one file:

```javascript
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

The manifest names `bin/tool`, not the `.mjs` file. It is a two-line shell
script that starts Node, and it exists because the app starts a tool with a
`PATH` that has no `node` in it: see
[What a tool must not assume](#what-a-tool-must-not-assume). It looks in
Homebrew's two places and where the installer from nodejs.org puts Node; if
yours is elsewhere, say so in it.

### In Python, with the kit

```sh
vitruvian-tool init ~/my-py-tool --id com.you.my-py-tool --name "My Python tool" --publisher "You" --template python-kit
/usr/bin/python3 -m pip install --target ~/my-py-tool/lib -r ~/my-py-tool/requirements.txt
vitruvian-tool validate ~/my-py-tool
vitruvian-tool run ~/my-py-tool
```

This writes the manifest, `bin/tool.py`, and a `requirements.txt` that names
[`vitruvian-tool-kit`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/kits/python) at the version of this SDK. The kit is
installed into `lib/`, inside the tool's folder, with Apple's `python3`,
because that is the one the app finds. The kit needs Python 3.9 or later and
nothing but the standard library. The program puts `lib/` on its path, then:

```python
tool = Tool(version="0.1.0")


@tool.command("hello")
def hello(app):
    app.notify.hud(icon="hand.wave", message="Hello from a Python tool, with the kit")


@tool.command("count")
def count(app):
    # The step is saved as text. The options are how the app draws the
    # setting, not a rule on what is saved: an app before 3.48 draws a text
    # field, so anything may be there. What is no number counts as one.
    step = str(app.storage.get(key="step").value)
    counted = app.storage.get(key="count").value + (int(step) if step.isdigit() else 1)
    app.storage.set(key="count", value=counted)
    app.notify.hud(icon="number", message=f"Counted to {counted}")


tool.run()
```

The plain Python tool above needs no kit and no install, and stays the
quickest start. The kit is for a tool with more than a few commands.

### The TypeScript and Python kits

Both kits are the Swift kit's shape, with one difference: a call on `app` is
named after its message. `notify/hud` is `app.notify.hud`, `storage/get` is
`app.storage.get`, and `log` is `app.log`. In Python a name in two words is
written with an underscore: `clipboard/readText` is
`app.clipboard.read_text`. Each call takes the message's params, by name, and
returns what the answer carries. The types are made from the schemas, so the
list of calls is the list of messages a tool may send, above.

- **A call can be refused.** It then throws a `Refusal` (TypeScript) or raises
  one (Python), whose `code` is the failure's. If your handler lets it
  through, the command is answered as refused. Throw or raise
  `CommandRefused("why")` to refuse a command yourself.
- **One thread, and synchronous.** A call to the app waits for its answer,
  ten seconds at most, and returns it as a value. A handler must not be
  `async`: the kit refuses a command whose handler is.
- **Never write to standard output.** No `console.log`, no `print`. Write to
  standard error, or call `app.log`.
- **Two calls are the kit's own**, beside the ones named after messages:
  `app.supports(name)` says whether the app named a feature at hello, and
  `app.status(state, ...)` sets the tool's status on the closed island, and
  sends nothing to an app that does not have one. `app.ui.status(...)` is
  the bare message, sent whatever the app said. "A status on the closed
  island", below, has both in use.
- `app.language` and `app.dataFolder` (`app.data_folder` in Python) are what
  the app said at hello; `tool.onStart`, `tool.onPreferencesChanged` and
  `tool.onLanguageChanged` (`on_start`, and so on, in Python) are called as in
  Swift.

To work from a checkout of this repository before a release of the kit, add
`--sdk packages/vitruvian-sdk` to `init`. The Python kit is then copied from
the checkout into `lib/`, and the TypeScript tool's `package.json` names the
kit by its path: build it once with `npm run build` in
`packages/vitruvian-sdk/kits/typescript`, then use `npm install --install-links`
in the tool's folder, so that a copy of the kit, not a link, goes in it.

### In Go or Rust, with a kit

```sh
vitruvian-tool init ~/my-go-tool --id com.you.my-go-tool --name "My Go tool" --publisher "You" --template go
vitruvian-tool init ~/my-rust-tool --id com.you.my-rust-tool --name "My Rust tool" --publisher "You" --template rust
~/my-go-tool/build.sh
vitruvian-tool validate ~/my-go-tool/tool
vitruvian-tool run ~/my-go-tool/tool
```

Each writes a program and, beside it, `tool/`: the folder you add to the
app. `build.sh` builds the program, with `go build` or `cargo build`, and
puts it in `tool/bin/`. The Go module requires
`github.com/VitruvianSoftware/vitruvian-sdk/go` and the Rust package
`vitruvian-tool-kit`, each at the version of the `vitruvian-tool` you ran,
so the first build fetches the kit. With `--sdk packages/vitruvian-sdk` the
tool builds against the kit in this repository instead, and fetches
nothing for Go.

The Go kit needs Go 1.22 or later and nothing outside Go's standard library.
The Rust kit needs Rust 1.75 or later and two crates, `serde` and
`serde_json`: Rust has no JSON of its own. Either way the program is one
file with nothing to install beside it.

A Go tool is one file:

```go
package main

import (
	"context"
	"fmt"

	"github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit"
)

func main() {
	tool := toolkit.New("0.1.0")

	tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
		return app.Notify.HUD("Hello from a Go tool", "hand.wave")
	})

	tool.Command("count", func(ctx context.Context, app *toolkit.App) error {
		saved, err := app.Storage.Get("count")
		if err != nil {
			return err
		}
		next, _ := saved.(float64)
		next++
		if err := app.Storage.Set("count", next); err != nil {
			return err
		}
		return app.Notify.HUD(fmt.Sprintf("Counted to %d", int(next)), "number")
	})

	tool.Run()
}
```

A Rust tool is one file too:

```rust
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
```

The calls are the Swift kit's, grouped by the service they need:

| In Go | In Rust | Message | In `uses` |
|---|---|---|---|
| `app.Notify.HUD` | `app.notify().hud` | `notify/hud` | `notify` |
| `app.Notify.Beep` | `app.notify().beep` | `notify/beep` | `notify` |
| `app.Open.URL` | `app.open().url` | `open/url` | `open` |
| `app.Clipboard.ReadText` | `app.clipboard().read_text` | `clipboard/readText` | `clipboard.read` |
| `app.Clipboard.WriteText` | `app.clipboard().write_text` | `clipboard/writeText` | `clipboard.write` |
| `app.Keystrokes.Paste` | `app.keystrokes().paste` | `keystrokes/paste` | `keystrokes` |
| `app.Keystrokes.PressMenuItem` | `app.keystrokes().press_menu_item` | `keystrokes/pressMenuItem` | `keystrokes` |
| `app.Processes.Terminate` | `app.processes().terminate` | `processes/terminate` | `processes` |
| `app.Storage.Get`, `app.Storage.Set` | `app.storage().get`, `app.storage().set` | `storage/get`, `storage/set` | `storage` |
| `app.SetRunnable` | `app.set_runnable` | `commands/state` | |
| `app.Log` | `app.log` | `log` | |
| `app.UI.Badge` | `app.ui().badge` | `ui/badge` | `notify` |
| `app.UI.Status` | `app.ui().status` | `ui/status` | |
| `app.Supports` | `app.supports` | what `initialize` said the app has | |

The three rules of the Swift kit hold for both. **A call can be refused**:
it returns the app's failure, a `*toolkit.Error` in Go and
`ToolError::App` in Rust, and a handler that returns it has its command
answered as refused; return `toolkit.Refuse("why")` or
`Err(ToolError::refused("why"))` to refuse a command yourself. **Handlers
run one at a time**, on the thread that called `Run` or `run`, and a call
waits there for its answer, ten seconds at most; one more thread reads
standard input, and what comes while a handler waits is handled after it.
**Never print to standard output**: it is the link.

In Go a handler is also handed a `context.Context`. It is done once the
app has said goodbye or gone away: a handler that works for long without
calling the app should watch it. `tool.OnPreferencesChanged` and
`tool.OnLanguageChanged`, in Rust `tool.on_preferences_changed` and
`tool.on_language_changed`, are the Swift kit's hooks.

For the two samples, build their folders with Bazel:

```sh
bazel build //packages/vitruvian-sdk:native-sample-folders
```

They are then in `bazel-bin/packages/vitruvian-sdk/built/`.

### A tool that does not ask the app

A tool may do anything itself. [`samples/front-window`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/front-window)
reads the title of the window in front by asking macOS, through
Accessibility. The protocol has no message for that, and the tool needs none:

```swift
func frontWindowTitle() throws -> String {
    guard let front = frontApp() else { throw refused("no app is in front") }
    AXUIElementSetMessagingTimeout(front, 1)
    guard let window = element(attribute(front, kAXFocusedWindowAttribute)),
          let title = attribute(window, kAXTitleAttribute) as? String
    else { throw refused("the app in front has no window with a title") }
    return title
}
```

Started by Vitruvian, it works once Vitruvian has Accessibility, with no
prompt of its own. Started from a terminal that lacks Accessibility, it
refuses its command and says why.

## The manifest, field by field

```json
{
  "id": "com.acme.deploys",
  "name": { "en": "Deploys", "fr": "Déploiements" },
  "description": { "en": "Copies the address of your latest deploy." },
  "version": "1.2.0",
  "protocol": "1",
  "publisher": "Acme",
  "license": "MIT",
  "icon": "shippingbox",
  "uses": ["clipboard.write", "notify", "storage"],
  "contributes": {
    "commands": [
      {
        "id": "copyLatest",
        "title": { "en": "Copy latest deploy" },
        "icon": "link",
        "surfaces": ["commandBar", "radial", "shortcut"]
      }
    ]
  },
  "preferences": [
    { "id": "project", "title": { "en": "Project" }, "type": "string", "default": "" }
  ],
  "activation": ["onCommand"],
  "runtime": { "kind": "external", "exec": "bin/deploys" }
}
```

| Field | Needed | What it is |
|---|---|---|
| `id` | yes | The tool's name to the app. Letters, digits, dots, hyphens and underscores, at most 128 characters, **with a dot**: `com.you.tool`. An id with no dot is one of the app's own tools and is refused. |
| `name` | yes | What the person sees. A map from a language tag to text. `en` is required. |
| `description` | no | One sentence, shown on the sheet. A map of languages, like `name`. |
| `version` | yes | Your own version, as text. Shown on the sheet, and again when the tool is updated. |
| `protocol` | yes | `"1"`, or `"2"` for a tool that draws. Version 2 adds `panels` and changes nothing else. |
| `publisher` | yes | Who made it. Shown beside the name. |
| `license` | no | Text. Not shown yet. |
| `icon` | no | An SF Symbol name. One the Mac does not have, or none, draws as a puzzle piece. |
| `uses` | no | The app services the tool calls: `notify`, `open`, `clipboard.read`, `clipboard.write`, `keystrokes`, `processes`, `storage`. A request for a service that is not listed is refused. **It is not a list of what the tool may do**: a tool may do anything. |
| `contributes` | no | Holds `commands`: at most 32. Each has an `id`, a `title` (a map of languages), an optional `icon`, and `surfaces`: where it is offered, any of `commandBar`, `radial`, `quickPanel`, `shortcut`. In protocol 2 it may hold `panels` too: "Drawing", below. And `status`, `{ "placement": "island" }`: the tool shows a small status mark on the closed island, which it sets with `ui/status`. `island` is the only placement. Without it the app refuses `ui/status`. |
| `preferences` | no | At most 16 values the app keeps for the tool. Each is `{ id, title, type, default }`; `type` is `string`, `boolean`, `integer` or `number`, and the default is of that type. `title` may be left out. It is what the setting is called to the person: a map of languages, like `name`, of at most 60 characters each, with no line break. A preference with a title is shown in the tool's detail in Settings, where the person can change it: a switch for `boolean`, a text field for `string`, a number field for `integer` and `number`. A preference with no title is the tool's alone and is never shown to the person. A `string` preference may carry `options`: from 1 to 64 of `{ value, title }`, and the app then draws a pop-up menu in place of the text field. A `value` is text of at most 128 characters, with no line break, and may be empty; no two options share one; the default is one of them. A `title` is a map of languages held to what the preference's own title is. The tool reads and writes any of them with `storage/get` and `storage/set`. |
| `activation` | no | `onCommand` (the default): started the first time one of its commands runs, stopped after two minutes with nothing asked of it. `onLaunch`: started with the app and kept running. |
| `runtime` | yes | `kind` is `"external"`. `exec` is the program, as a path inside the folder. |

- **Text in several languages** is looked up by the app's language: its own
  entry (`pt-BR`), else the language without the region (`pt`), else English.
  The app shows your words as you wrote them and never translates them.
- **A field the app does not know is ignored.** A service, a surface, a
  preference type or an activation it does not know refuses the whole tool,
  and the reason names it.
- **A preference's `title` is newer than the rest of the manifest.** An app
  from before it ignores the field, as it ignores any field it does not
  know: the tool is added and runs there as before, and the person is shown
  no setting. The manifest has no field for the oldest app a tool needs, and
  a title needs none.
- **`options` and `status` are newer still**, from Vitruvian 3.48. An app
  from before them ignores both fields: a preference with options is a text
  field there, holding the same text, and the tool shows no status. So the
  options are how the app draws, never a rule on the value: the app keeps a
  saved value that is no option's and shows it as written.
- **Never write a preference `type` the table above does not list.** A list
  of choices is `"type": "string"` with `options`. A type an app does not
  know refuses the whole tool, on every app released so far.
- **The file is at most 65,536 bytes.**

## Every message

A message is one line of JSON-RPC 2.0. A **request** has an `id` and is
answered, with a result or a failure that carries the same `id`. A **notice**
has no `id` and is not answered. A request that was simply done is answered
with `{}`.

### What the app sends

`initialize` is always first. Answer it before you send anything else. You
have ten seconds; for everything after it, two.

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1","2"],"language":"en-US","dataFolder":"/Users/you/Library/Application Support/com.vitruviansoftware.vitruvian/ToolData/com.acme.deploys","features":["ui.status","ui.choice","preferences.options"]}}
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","toolVersion":"1.2.0"}}
```

`features` names what this app has beyond the first release of the protocol
version: `ui.status` (the `ui/status` request), `ui.choice` (the `choice`
block) and `preferences.options` (a preference's `options`, drawn as a
menu). Vitruvian 3.48 and later send it. An older app sends no `features`
at all, and has none of them. Ignore a name you do not know.

`command/run` runs a command, named by the id the manifest gives it. Answer
`{}` when it ran, or failure -32010 when you will not run it.

```json
{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"copyLatest"}}
{"jsonrpc":"2.0","id":2,"result":{}}
```

```json
{"jsonrpc":"2.0","id":3,"method":"command/run","params":{"command":"copyLatest"}}
{"jsonrpc":"2.0","id":3,"error":{"code":-32010,"message":"no deploy yet"}}
```

`preferences/changed` is a notice: the person changed one of your preferences
in the tool's detail in Settings. It carries the id and the new value of each
preference that changed; today that is one at a time. It is sent only to a
tool that is running and has answered `initialize`. A tool that is not
running is not started for it, and reads the value with `storage/get` when it
next starts. What your own `storage/set` saved is not sent back to you.

`language/changed` is a notice too: the person changed the app's language in
Settings. It carries the new language as a tag, the same kind `initialize`
carries. Like `preferences/changed` it is sent only to a tool that is
running and has answered `initialize`, once for each change. A tool that is
not running is not started for it: `initialize` tells it the language when
it next starts. An app from before 2026-10-12 never sent it, so a tool
there learns the language only when it starts.

```json
{"jsonrpc":"2.0","method":"preferences/changed","params":{"values":{"project":"web"}}}
{"jsonrpc":"2.0","method":"language/changed","params":{"language":"fr"}}
```

`shutdown` means stop. The app then closes your input. Exit with 0 within two
seconds.

```json
{"jsonrpc":"2.0","method":"shutdown"}
```

### What a tool sends

`commands/state` says which commands can run now. It carries the whole list
every time. Until you send one, all of them can. `log` writes a line to the
tool's log.

```json
{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["copyLatest"]}}
{"jsonrpc":"2.0","method":"log","params":{"message":"fetched 3 deploys"}}
```

Everything else is a request, so the app can refuse it. You pick the `id`.

```json
{"jsonrpc":"2.0","id":"a","method":"notify/hud","params":{"icon":"link","message":"Copied the address"}}
{"jsonrpc":"2.0","id":"a","result":{}}
```

```json
{"jsonrpc":"2.0","id":"b","method":"notify/beep"}
{"jsonrpc":"2.0","id":"b","result":{}}
```

```json
{"jsonrpc":"2.0","id":"c","method":"open/url","params":{"url":"https://example.com/deploys/41"}}
{"jsonrpc":"2.0","id":"c","result":{"opened":true}}
```

`clipboard/readText` leaves `text` out when the clipboard holds no text.

```json
{"jsonrpc":"2.0","id":"d","method":"clipboard/readText"}
{"jsonrpc":"2.0","id":"d","result":{"text":"what was copied"}}
```

```json
{"jsonrpc":"2.0","id":"e","method":"clipboard/writeText","params":{"text":"https://example.com/deploys/41"}}
{"jsonrpc":"2.0","id":"e","result":{"written":true}}
```

```json
{"jsonrpc":"2.0","id":"f","method":"keystrokes/paste","params":{"text":"pasted into the app in front"}}
{"jsonrpc":"2.0","id":"f","result":{}}
```

`keystrokes/pressMenuItem` takes a list of key equivalents, and presses the
menu item of the app in front that has one of them. Command is always part of
an equivalent; `modifiers` names what is held with it.

```json
{"jsonrpc":"2.0","id":"g","method":"keystrokes/pressMenuItem","params":{"equivalents":[{"character":"c","modifiers":[]},{"character":"c","modifiers":["shift"]}]}}
{"jsonrpc":"2.0","id":"g","result":{"pressed":true}}
```

`processes/terminate` ends a process with the app's checks. `force` true ends
it at once; false asks it to quit.

```json
{"jsonrpc":"2.0","id":"h","method":"processes/terminate","params":{"pid":4242,"name":"node","force":false}}
{"jsonrpc":"2.0","id":"h","result":{}}
```

`storage/get` and `storage/set` read and write a preference the manifest
declares, by its id. A value is text, yes or no, or a number. Text is at most
4,096 characters: a longer one is answered with failure -32602, and nothing
is saved.

```json
{"jsonrpc":"2.0","id":"i","method":"storage/get","params":{"key":"project"}}
{"jsonrpc":"2.0","id":"i","result":{"value":"web"}}
```

```json
{"jsonrpc":"2.0","id":"j","method":"storage/set","params":{"key":"project","value":"api"}}
{"jsonrpc":"2.0","id":"j","result":{}}
```

### What version 2 adds

Protocol 2 adds six messages, for a tool that draws: its manifest says
`"protocol": "2"` and lists `panels`. Nothing of version 1 changes, and a
tool that draws nothing never sees them. "Drawing", below, says how a tool
uses them.

`ui/open` asks for a panel's first page; `ui/event` says what the person did
in it, and the answer is the next page, or `keep`. `ui/close` says the panel
went away.

```json
{"jsonrpc":"2.0","id":14,"method":"ui/open","params":{"panel":"deploys"}}
{"jsonrpc":"2.0","id":14,"result":{"tree":{"blocks":[{"type":"heading","text":"Today"},{"type":"button","id":"again","title":"Deploy again"}]}}}
{"jsonrpc":"2.0","id":15,"method":"ui/event","params":{"panel":"deploys","block":"again","event":"tap"}}
{"jsonrpc":"2.0","id":15,"result":{"keep":true}}
{"jsonrpc":"2.0","method":"ui/close","params":{"panel":"deploys"}}
```

`ui/render` sends a new page for a panel that is open, when the tool has
news. `ui/badge` puts a count or a dot beside the tool in the island; it needs
`notify` in `uses`.

```json
{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":{"blocks":[{"type":"text","text":"Nothing deployed today."}]}}}
{"jsonrpc":"2.0","id":"l","method":"ui/badge","params":{"count":2}}
{"jsonrpc":"2.0","id":"l","result":{}}
```

`ui/status` sets the tool's status: a small mark the app draws on the closed
island. `state` is `none`, `ok`, `busy`, `attention` or `failure`. `text`, a
string or a map of languages, says what it means, for VoiceOver. `icon`, an
SF Symbol name, replaces the state's own glyph. It needs nothing in `uses`:
the manifest declares it, under `contributes.status`, and without that the
app answers failure -32602. Each one replaces the last, and the mark goes
when your program ends. An app before 3.48 answers failure -32601.

```json
{"jsonrpc":"2.0","id":"m","method":"ui/status","params":{"state":"busy","icon":"arrow.triangle.branch","text":{"en":"Checks are running","fr":"Vérifications en cours"}}}
{"jsonrpc":"2.0","id":"m","result":{}}
{"jsonrpc":"2.0","id":"n","method":"ui/status","params":{"state":"none"}}
{"jsonrpc":"2.0","id":"n","result":{}}
```

### Being refused

Any request can be refused, at any time. Your tool must cope.

```json
{"jsonrpc":"2.0","id":"k","method":"open/url","params":{"url":"https://example.com"}}
{"jsonrpc":"2.0","id":"k","error":{"code":-32001,"message":"not listed in uses","data":{"service":"open"}}}
```

| Code | Meaning |
|---|---|
| -32001 | The service is not in your manifest's `uses`. `data.service` names it. |
| -32002 | The tool is not installed, or is switched off. |
| -32003 | Vitruvian lacks a macOS permission the service needs. `data.permission` names it. |
| -32004 | Not available right now. |
| -32010 | Yours: you will not run the command. |
| -32601 | A method the other side does not know. |
| -32602 | Params that are not the message's own, a command you do not have, a preference the manifest does not declare, a value of the wrong kind, or text over 4,096 characters. |

## Drawing

A tool of protocol 2 can show the person a page of its own, in three places:
a page in the island's Tools area, a part of the tool's detail in Settings,
and a window. It describes the page as a list of blocks and the app draws
them, with its own controls, in the person's light or dark appearance and at
the island's small size. Or it brings a web page from its own folder, for
what blocks cannot carry. A tool of protocol 1 draws nothing and changes
nothing by staying one.

Each place is a panel, in the manifest:

```json
{
  "id": "com.acme.deploys",
  "name": { "en": "Deploys" },
  "version": "2.0.0",
  "protocol": "2",
  "publisher": "Acme",
  "uses": ["notify", "open"],
  "contributes": {
    "panels": [
      { "id": "deploys", "title": { "en": "Deploys" }, "placement": "island", "icon": "shippingbox" },
      { "id": "settings", "title": { "en": "Deploys" }, "placement": "settings" },
      { "id": "dashboard", "title": { "en": "Dashboard" }, "placement": "window", "kind": "web", "entry": "ui/dashboard.html" }
    ]
  },
  "runtime": { "kind": "external", "exec": "bin/deploys" }
}
```

- **At most 8 panels**, one in the island and one in Settings at most; any
  number of the rest are windows. A window opens when the person asks: from
  the tool's detail in Settings, or in answer to something they did in
  another of the tool's panels.
- **`kind`** is `blocks`, which you may leave out, or `web`, which needs an
  `entry`: a path inside the folder, like `runtime.exec`.
- **The person decides** whether the island lists your page, with a switch in
  the tool's detail. It is on until they turn it off.

When the person opens a panel the app asks for its first page with
`ui/open`, starting your program first if it is not running. While a panel
is open your program is not stopped for being idle. What the person does is
a `ui/event`, answered with the next page; `ui/close` says the panel went
away. To change an open page by yourself, send `ui/render`. "What version 2
adds", above, shows each message.

### The thirteen kinds of block

| Kind | Fields | What the person does |
|---|---|---|
| `text` | `text`, `style` (`body`, `secondary`, `caption`, `monospaced`), `lines` (1 to 10; 4 when left out) | |
| `heading` | `text`; two lines at most | |
| `row` | `title`, `subtitle`, `icon`, `trailing` | taps it, when it has an `id`: `tap` |
| `button` | `title`, `style` (`plain`, `prominent`, `destructive`), `enabled`; needs an `id` | presses it: `tap` |
| `toggle` | `title`, `value`, `enabled`; needs an `id` | turns it: `toggle`, with the new state |
| `field` | `title`, `value`, `placeholder`, `kind` (`text`, `number`, `secret`); needs an `id` | presses Return: `submit`; leaves it changed: `change`; each with the text |
| `list` | `rows`, each `{ id, title, subtitle, icon, trailing }`, at most 200; needs an `id` | taps a row: `tap`, with the row's id |
| `progress` | `value` from 0 to 1, or none when nobody knows; `label` | |
| `image` | `source`: a path inside your folder, or a `data:` PNG or JPEG; `alt`; `height` up to 300 | |
| `divider` | none | |
| `link` | `title`, `url`: a web or mail address, opened through the app, so it needs `open` in `uses` | clicks it |
| `spacer` | `size`, up to 40 points | |
| `choice` | `title`, `value`, `options`, each `{ value, title }`, from 1 to 64, no two with one `value`; `enabled`; needs an `id` | picks an option: `change`, with the option's `value` |

Any text is a string or a map of languages, and it is drawn as you wrote it:
never as markdown, never as a link, and cut to its lines. A block of a kind
this app does not know, from a later protocol, is drawn as its `fallback`
text, or left out. `choice` is such a kind to an app before 3.48: it is in
the hello's `features` as `ui.choice`, and a tool sends a `field` to an app
that does not name it. A page is at most 262,144 bytes and 200 blocks; one over
either is not drawn, the panel keeps the page it had, and your log says why.

### In Swift, with the kit

[`samples/hello-panel-swift`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-panel-swift) is a counter
in the island and a switch in Settings. A page is written as the blocks it
holds, one function for each kind:

```swift
    func page(_ app: App) -> UITree {
        UITree {
            heading("Counter")
            text("Pressed \(count) times")
            button("add", "Add \(step)", style: .prominent)
            field("name", title: "Your name", value: name, placeholder: "Type it and press Return")
            if !name.isEmpty { text("Hello, \(name)", style: .secondary) }
            statusPicker(app)
        }
    }
```

`tool.panel` says what a panel shows when it opens, and what each thing the
person does gives. The handle it returns sends a page unprompted, with
`render`, and sets the tool's badge in the island, with `badge`:

```swift
let island = tool.panel("counter", onOpen: { app, _ in counter.page(app) }, onEvent: { app, panel, event in
    switch event.block {
    case "add"?:
        counter.count += counter.step
        try panel.badge(count: counter.count)
    case "name"?:
        counter.name = event.text ?? counter.name
    case "status"?:
        // A pick is the event `change`, as leaving a field changed is.
        guard let picked = event.text.flatMap(StatusState.init(rawValue:)) else { return .keep }
        counter.status = picked
        try counter.showStatus(app)
    default:
        return .keep
    }
    return .page(counter.page(app))
})
```

```swift
tool.command("addOne") { app in
    counter.count += counter.step
    island.render(counter.page(app))
}
```

An answer is `.page`, `.keep`, `.open` with one of your window panels, or
`.reply` for a web page's call. `render` sends nothing while the panel is
not open, and the app draws at most four pages a second for a panel: send
fewer.

### In TypeScript, with the kit

[`samples/hello-panel-typescript`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-panel-typescript) is
the same counter, in plain JavaScript that Node runs. A page is `tree` of
its blocks, one function for each kind, and a block that is `false` is left
out:

```javascript
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
  ]);
}
```

`tool.panel` takes the two handlers by name. An answer is `{ page }`,
`{ keep: true }`, `{ open }` with one of your window panels, or `{ reply }`
for a web page's call; `event.text` and `event.isOn` are what a field and a
switch carry, and `event.row` the row of a list that was tapped:

```javascript
const island = tool.panel("counter", {
  onOpen: (app) => page(app),
  onEvent: (app, panel, event) => {
    switch (event.block) {
      case "add":
        counter.count += step();
        panel.badge({ count: counter.count });
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
      default:
        return { keep: true };
    }
    return { page: page(app) };
  },
});
```

A web panel's `onCall` is `panel.onCall = (app, method, params) => ...`; throw
a `Refusal` to refuse a call.

### In Python, with the kit

[`samples/hello-panel-python`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-panel-python) is the same
counter again. A page is `tree` of its blocks, one function for each kind,
and a block that is `None` is left out; `list` is `list_`, as Python has the
word:

```python
    def page(self, app):
        """The island page: what it says now."""
        return tree(
            heading("Counter"),
            text(f"Pressed {self.count} times"),
            button("add", f"Add {self.step}", style="prominent"),
            field(
                "name",
                title="Your name",
                value=self.name,
                placeholder="Type it and press Return",
            ),
            text(f"Hello, {self.name}", style="secondary") if self.name else None,
            self.status_picker(app),
        )
```

`tool.panel` takes the two handlers by name. An answer is one of
`PanelAnswer`'s four: `page(tree)`, `keep()`, `open(panel)` with one of your
window panels, or `reply(value)` for a web page's call; `event.text` and
`event.is_on` are what a field and a switch carry, and `event.row` the row
of a list that was tapped:

```python
def island_event(app, panel, event):
    if event.block == "add":
        counter.count += counter.step
        panel.badge(count=counter.count)
    elif event.block == "name":
        counter.name = event.text if event.text is not None else counter.name
    elif event.block == "status":
        # A pick is the event change, as leaving a field changed is.
        if event.text not in STATUSES:
            return PanelAnswer.keep()
        counter.status = event.text
        counter.show_status(app)
    else:
        return PanelAnswer.keep()
    return PanelAnswer.page(counter.page(app))


island = tool.panel(
    "counter", on_open=lambda app, panel: counter.page(app), on_event=island_event
)
```

A web panel's `on_call` is `panel.on_call = lambda app, method, params: ...`;
raise a `Refusal` to refuse a call.

### In Go, with the kit

[`samples/hello-panel-go`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-panel-go) is the same
counter, with package `ui` of the kit. A page is `ui.Tree` of its blocks,
one function for each kind; what a block may carry beyond its words is an
options struct, left out when there is none, and `ui.If` leaves a block
out:

```go
// page is the island page: what it says now.
func (c *counter) page(app *toolkit.App) toolkit.UITree {
	return ui.Tree(
		ui.Heading("Counter"),
		ui.Text(fmt.Sprintf("Pressed %d times", c.count)),
		ui.Button("add", fmt.Sprintf("Add %d", c.step()), ui.ButtonOptions{Style: ui.Prominent}),
		ui.Field("name", ui.FieldOptions{Title: "Your name", Value: c.name, Placeholder: "Type it and press Return"}),
		ui.If(c.name != "", ui.Text("Hello, "+c.name, ui.TextOptions{Style: ui.Secondary})),
		c.statusPicker(app),
	)
}
```

`tool.Panel` takes the two handlers: the first gives a `*toolkit.UITree`,
nil for a web panel; the second answers what the person did with
`toolkit.Page`, `toolkit.Keep`, `toolkit.OpenWindow` with one of your window
panels, or `toolkit.Reply` for a web page's call. `event.Text()` and
`event.IsOn()` are what a field and a switch carry, and `event.Row()` the
row of a list that was tapped. The handle it returns sends a page
unprompted, with `Render`, and sets the tool's badge in the island, with
`Badge`:

```go
	island := tool.Panel("counter",
		func(app *toolkit.App, panel *toolkit.PanelHandle) (*toolkit.UITree, error) {
			page := state.page(app)
			return &page, nil
		},
		func(app *toolkit.App, panel *toolkit.PanelHandle, event toolkit.PanelEvent) (toolkit.PanelAnswer, error) {
			switch event.Block {
			case "add":
				state.count += state.step()
				if err := panel.Badge(state.count, false); err != nil {
					return toolkit.Keep(), err
				}
			case "name":
				if text, ok := event.Text(); ok {
					state.name = text
				}
			case "status":
				// A pick is the event change, as leaving a field changed is.
				picked, ok := event.Text()
				if !ok || !isStatus(picked) {
					return toolkit.Keep(), nil
				}
				state.status = picked
				if _, err := state.showStatus(app); err != nil {
					return toolkit.Keep(), err
				}
			default:
				return toolkit.Keep(), nil
			}
			return toolkit.Page(state.page(app)), nil
		})
```

```go
	tool.Command("addOne", func(ctx context.Context, app *toolkit.App) error {
		state.count += state.step()
		island.Render(state.page(app))
		return nil
	})
```

A web panel's `OnCall` is `panel.OnCall = func(app *toolkit.App, method
string, params any) (any, error) { ... }`; return a `*toolkit.Error` to
refuse a call. A handler's error refuses what the app asked: a
`*toolkit.Error` as it is, anything else as an internal error with its
words.

### In Rust, with the kit

[`samples/hello-panel-rust`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/samples/hello-panel-rust) is the same
counter. A page is `tree!` of its blocks, one function for each kind; what
a block may carry beyond its words is set with a method, and an item that
is `None` is left out:

```rust
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
        ]
    }
```

`tool.panel` takes the two handlers: the first gives `Some` page, or `None`
for a web panel; the second answers what the person did with one of
`PanelAnswer`'s four: `Page(tree)`, `Keep`, `Open(panel)` with one of your
window panels, or `Reply(value)` for a web page's call. `event.text()` and
`event.is_on()` are what a field and a switch carry, and `event.row()` the
row of a list that was tapped. The handle it returns is cheap to clone and
is the same panel: it sends a page unprompted, with `render`, and sets the
tool's badge in the island, with `badge`, each given the `app` of the
handler it is called from:

```rust
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
                _ => return Ok(PanelAnswer::Keep),
            }
            Ok(PanelAnswer::Page(counter.page(app)))
        },
    );
```

```rust
    let counted = counter.clone();
    tool.command("addOne", move |app| {
        let mut counter = counted.borrow_mut();
        let step = counter.step();
        counter.count += step;
        island.render(app, &counter.page(app));
        Ok(())
    });
```

A web panel's `on_call` is `panel.on_call(|app, method, params| ...)`;
return `Err(ToolError::App(...))` to refuse a call. A handler's error
refuses what the app asked: the app's failure as it is, anything else as an
internal error with its words.

### A web page

A `web` panel shows `entry`, a page in your folder. It may load what else is
in your folder, and use the network itself; it may not go to another page
outside the folder, or open a window. Before its scripts run the app gives
it `window.vitruvian`:

```text
const saved = await window.vitruvian.call("notify/hud", { icon: "checkmark", message: "Saved" });
const count = await window.vitruvian.call("tool/count", { by: 2 });
window.vitruvian.on("language/changed", (params) => draw(params.language));
document.body.dataset.appearance = window.vitruvian.appearance;
```

A call goes to your program as a `ui/event` whose event is `bridge`, and
the answer's `reply` is what the page gets back. A request the app does,
such as `notify/hud`, is checked against your `uses` first; the kit then
asks the app for it as your tool's own. A method that starts with `tool/` is
yours, and the kit hands it to the panel's `onCall`. Anything else is
refused, and a refusal rejects the page's promise with its code and words.
`on` hears `preferences/changed` and `language/changed`, with the params
your program is sent.

### A status on the closed island

A tool can show a small mark on the closed island, beside the agent mark: a
green tick, an orange mark that breathes, a yellow one, a red warning. It is
how a tool says "all is well" or "look at this" without the person opening
anything. The app draws the mark, in its own style. The tool only says which.

First the manifest says the tool has a status, under `contributes`. It is
protocol 2's, and it needs nothing in `uses`:

```json
{
  "id": "com.acme.deploys",
  "name": { "en": "Deploys" },
  "version": "2.1.0",
  "protocol": "2",
  "publisher": "Acme",
  "contributes": {
    "panels": [
      { "id": "deploys", "title": { "en": "Deploys" }, "placement": "island" }
    ],
    "status": { "placement": "island" }
  },
  "activation": ["onLaunch"],
  "runtime": { "kind": "external", "exec": "bin/deploys" }
}
```

Then the tool sets it with `ui/status`, whenever it changes. Each one
replaces the last.

| `state` | What the person sees | Say it when |
|---|---|---|
| `none` | no mark | there is nothing to say |
| `ok` | a green tick, still | all is well |
| `busy` | an orange mark that breathes; still with Reduce Motion on | something is under way |
| `attention` | a yellow mark in a circle, still | something waits for the person |
| `failure` | a red warning triangle, still | something failed |

`text` is one short line that says what the status means. VoiceOver reads it
after the tool's name, as part of the closed island's button, and it is the
tooltip. Leave it out and the app says
its own word for the state. `icon` is an SF Symbol name that replaces the
state's glyph; the colour, the size and the breathing stay the app's.

- **There is one mark, and the worst one wins**: `failure`, then
  `attention`, then `busy`, then `ok`. Every tool's status and the app's own
  GitHub mark compete for it. On a tie the app's mark wins, then the tool
  that was added first. So a quiet `ok` may not be the mark the person sees.
- **It is shown where the island rests on its agent wings**: with "While
  inactive" set to Agents, and no activity such as music in their place.
  While an agent session is running, the closed island shows that agent's
  activity in place of its resting wings, so neither the app's own mark nor
  a tool's is visible until the session ends.
- **A click on it opens your island page**, unless the mark is green or you
  have no island page the island lists. Then the click does what it always
  did.
- **It goes when your program ends**, for any reason: it crashed, was
  stopped, switched off, updated or removed, or it rested after two idle
  minutes. A tool that wants its status to last starts with the app,
  `"activation": ["onLaunch"]`, and sets its status each time it starts.
- **The person can switch it off**, in the tool's detail in Settings. You are
  not told: your `ui/status` is answered with `{}` all the same.
- **The app shows at most one change a second** for each tool, the newest
  one. Send a status when it changes, not on a timer.

Each kit has one call for it. It sends nothing, and says so, to an app that
does not have a status: "What an older app does", below.

```swift
    /// Sets the mark on the closed island. Nothing is sent to an app that
    /// has no status, and the call says so.
    func showStatus(_ app: App) throws {
        let says = Counter.statuses.first { $0.state == status }?.says
        try app.status(status, text: says.map(UIText.plain))
    }
```

```javascript
function showStatus(app) {
  const says = STATUSES.find(({ state }) => state === counter.status)?.says;
  return app.status(counter.status, says === undefined ? {} : { text: says });
}
```

```python
    def show_status(self, app):
        """Sets the mark on the closed island. Nothing is sent to an app that
        has no status, and the call says so."""
        return app.status(self.status, text=STATUSES[self.status][1])
```

```go
func (c *counter) showStatus(app *toolkit.App) (bool, error) {
	for _, status := range statuses {
		if status.state == c.status && status.says != "" {
			return app.UI.Status(c.status, toolkit.StatusOptions{Text: status.says})
		}
	}
	return app.UI.Status(c.status)
}
```

```rust
    fn show_status(&self, app: &mut App<'_>) -> Result<bool, ToolError> {
        let says = STATUSES
            .iter()
            .find(|(state, _, _)| *state == self.status)
            .and_then(|(_, _, says)| *says);
        app.ui().status(&self.status, says.map(Into::into), None)
    }
```

The samples set it when the program starts, since that is when it is gone:

```swift
// The status goes when the program ends, so it is set each time the program
// starts. The app may refuse any request: the tool carries on without.
tool.onStart = { app in
    do {
        try counter.showStatus(app)
    } catch {
        app.log("no status: \(error)")
    }
}
```

### A choice among fixed options

Where the person picks one of a few fixed values, the app draws a pop-up
menu. There are two places for one.

**A setting.** A `string` preference with `options` is drawn as a menu in the
tool's detail in Settings, in place of a text field:

```json
{
  "id": "com.acme.deploys",
  "name": { "en": "Deploys" },
  "version": "2.1.0",
  "protocol": "2",
  "publisher": "Acme",
  "uses": ["storage"],
  "preferences": [
    {
      "id": "light",
      "title": { "en": "Mouse when green" },
      "type": "string",
      "default": "green",
      "options": [
        { "value": "green", "title": { "en": "Green", "fr": "Vert" } },
        { "value": "breathe green", "title": { "en": "Pulsing green", "fr": "Vert pulsé" } }
      ]
    }
  ],
  "runtime": { "kind": "external", "exec": "bin/deploys" }
}
```

A pick is saved at once, and a running tool is sent `preferences/changed`,
as for any setting. The value is text: the tool reads and writes it with
`storage/get` and `storage/set` exactly as before.

- **The options are how the app draws the setting. They are no rule on the
  value.** The app never refuses a value that is none of them, and never
  changes one. A value saved before the tool had options, or one the tool
  wrote itself, is shown as the menu's first row, as written, until the
  person picks another.
- **So read the value as text that may be anything**, and fall back when it
  is none you know. `hello-swift` and `hello-python-kit` do, for their
  setting "Count by".
- **From 1 to 64 options**, no two with one `value`, and the default is one
  of them. A `value` is at most 128 characters and may be empty. A `title`
  is a map of languages, at most 60 characters each.

**A block on a page.** `choice` is a menu among a page's blocks:

```json
{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":{"blocks":[{"type":"choice","id":"light","title":"Mouse when green","value":"green","options":[{"value":"green","title":"Green"},{"value":"breathe green","title":{"en":"Pulsing green","de":"Pulsierendes Grün"}}],"fallback":"Mouse when green: Green"}]}}}
{"jsonrpc":"2.0","id":31,"method":"ui/event","params":{"panel":"deploys","block":"light","event":"change","value":"breathe green"}}
{"jsonrpc":"2.0","id":31,"result":{"keep":true}}
```

Picking an option is the event `change`, with the option's `value`: the event
a field sends when it is left with other text, so a tool that reads a
field's events reads a choice's. `value` is what is selected; one that is no
option's is drawn as an extra first row, as for a setting.

A `choice` is a kind of block an app before 3.48 does not know. There it is
drawn as its `fallback`, plain words nobody can change. So a tool asks first
and sends a `field` in its place. Each kit's builder writes a fallback when
you give none: the title, a colon and the selected option's title.

```swift
    /// The status, to pick: a pop-up menu where the app has one. An app
    /// before 3.48 draws a `choice` as plain words nobody can change, so
    /// there it is a field to type the word in.
    func statusPicker(_ app: App) -> UIBlock {
        guard app.supports(.choice) else {
            return field("status", title: "Status: none, ok, busy, attention or failure", value: status.rawValue)
        }
        let options = Counter.statuses.map { UIChoiceOption(value: $0.state.rawValue, title: .plain($0.title)) }
        return choice("status", title: "Status on the closed island", value: status.rawValue, options: options)
    }
```

```javascript
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

```python
    def status_picker(self, app):
        """The status, to pick: a pop-up menu where the app has one. An app
        before 3.48 draws a `choice` as plain words nobody can change, so
        there it is a field to type the word in."""
        if not app.supports(Feature.CHOICE):
            return field(
                "status",
                title="Status: none, ok, busy, attention or failure",
                value=self.status,
            )
        options = [
            UIChoiceOption(value=state, title=title)
            for state, (title, _) in STATUSES.items()
        ]
        return choice(
            "status", self.status, options, title="Status on the closed island"
        )
```

```go
func (c *counter) statusPicker(app *toolkit.App) toolkit.UIBlock {
	if !app.Supports(toolkit.FeatureChoice) {
		return ui.Field("status", ui.FieldOptions{Title: "Status: none, ok, busy, attention or failure", Value: c.status})
	}
	options := make([]toolkit.UIChoiceOption, 0, len(statuses))
	for _, status := range statuses {
		options = append(options, toolkit.UIChoiceOption{Value: status.state, Title: status.title})
	}
	return ui.Choice("status", c.status, options, ui.ChoiceOptions{Title: "Status on the closed island"})
}
```

```rust
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
```

### What an older app does

The status, the `choice` block and a preference's `options` were added to
protocol 2 in Vitruvian 3.48, with no new version. A tool that uses them
still installs and runs on 3.46 and 3.47. There it shows less, and nothing
breaks.

The app says what it has. `initialize` carries `features`, a list of names,
and an app before 3.48 sends none. Each kit keeps the list and answers
`supports`:

| What your tool does | Vitruvian 3.46 and 3.47 | Vitruvian 3.48 and later |
|---|---|---|
| Its manifest has `contributes.status` | The key is ignored. The tool is added and runs. | The sheet that asks before the tool is added says so, and the tool's detail has a switch for it. |
| It sets a status with a kit | The kit sends nothing, and the call says the status is not shown. | The mark is drawn. |
| It sends `ui/status` with no kit | Answered with failure -32601, "unknown method". Harmless. Stop asking. | The mark is drawn. |
| A preference has `options` | A text field, holding the same text. | A pop-up menu. |
| A page has a `choice` block | Its `fallback`, as plain words. So check `supports` and send a `field`. | A pop-up menu. |
| A preference has a `type` the table of the manifest does not list | **The tool is refused.** | **The tool is refused.** |

- **Never write a preference `type` the manifest's table does not list**,
  such as `"type": "choice"`. Every app refuses the whole tool for a type it
  does not know, and tells the person the tool's author made a mistake. A
  list of choices is `"type": "string"` with `options`.
- **The same goes for a `uses` entry, a surface, a panel's placement and an
  activation**: a name the app does not know refuses the tool. A key it does
  not know is ignored. That is why a status is a key under `contributes` and
  not an entry of `uses`.
- **`vitruvian-tool run` and the conformance script say hello as 3.48 does.**
  The script then starts your tool once more as an older app would, with no
  `features`, and answers `ui/status` with -32601. A tool that stops there,
  or keeps asking, fails that step.

## Limits, and what happens when a tool crosses them

The limits keep the app responsive. They are not there to protect anyone from
the tool.

| What a tool does | What the app does |
|---|---|
| Exits or crashes | Its commands grey out. The person is told once, in the app's short on-screen message. It is started again at the next need, after a wait that doubles from 1 second to 5 minutes. |
| Crashes three times within a minute | It stays stopped until the person clicks Start Again in Settings. |
| Does not answer `initialize` within 10 seconds, or anything else within 2 | The request fails. Three in a row, and the tool is treated as crashed. |
| Closes its output and keeps running | Nothing, at first. The app notices only when three requests in a row have gone unanswered. |
| Sends a line over 1,048,576 bytes (1 MB) | Stopped, and treated as crashed. |
| Sends more than 200 lines in one second | Each request past the 200th in that second is refused with -32004, and the app does no work for it. |
| Does that for 5 seconds in a row | Stopped, and treated as crashed. |
| Sends a line that is not a message | The line is dropped. Twenty in a minute, and the tool is stopped. |
| Writes to standard error | Kept as its log, up to 256 KB. Never shown as a message. |
| Ends its last line with no line break | That line is never read. |
| Is told `shutdown` and stays | Asked to end after 2 seconds, killed 1 second after that. |
| Is still running when the person removes it | The same, faster: asked to end after half a second, killed a quarter of a second later. Do not count on time to tidy up. |
| Starts a program of its own and leaves it running | The program is ended with the tool: asked to end when the tool is, killed when the tool is, and killed when the tool exits by itself, crashes or is stopped for being idle. Only a program that left the tool's process group is not. |
| Sends more than four pages a second for one panel | The ones between are not drawn: the last one is, when the second allows. |
| Sends more than forty pages in one second for one panel | Stopped, and treated as crashed. |
| Sends a page over 262,144 bytes or 200 blocks, or one a block of which is not well formed | Not drawn. The panel keeps the page it had, and the log says why. |
| Its web page makes more than 200 calls in one second, for 5 seconds | The same as the lines above: refused, then stopped. |
| Ends while a panel is open | The panel closes: the island goes back to its tiles, a window closes. |

A folder is refused, before anything is copied, when it holds more than
256 MB or more than 10,000 files, folders and links together. Keep build
output and dependencies you do not ship out of it.

## Adding it to the app

1. Open Vitruvian's Settings, then Features, and scroll to **Tools from
   outside**.
2. Click **Add a Tool…** and choose the tool's folder.
3. Read the sheet. It names the tool, its publisher and its commands, and
   says that the tool can do anything Vitruvian can. Click **Add Tool**.

The app copies the folder and runs the copy, so the original may move. The
copy is in
`~/Library/Application Support/com.vitruviansoftware.vitruvian/Tools/<id>/`.
What the tool saves goes in `ToolData/<id>/` beside it, which is also the
folder the program is started in.

- **To update a tool**, open its row, click **Update from Folder…**, and
  choose the folder again. The sheet shows the old and the new version.
- **A changed copy is not run.** If the manifest in the app's copy is not,
  byte for byte, the one the person agreed to, the tool is listed and never
  started, until it is updated from its folder.
- **"Changed" means the manifest, and only the manifest.** The app compares
  that one file. A program or any other file that changed, with the manifest
  as it was, is not noticed: not in the app's copy, and not on the sheet when
  a tool is updated.
- **A downloaded tool** carries macOS's quarantine mark, and the app refuses
  it. The app never clears the mark. The person can:
  `xattr -dr com.apple.quarantine <the folder>`.
- **A tool's settings** are in its detail: open its row. Each preference
  with a title is listed there under "Settings", and a change is saved at
  once and sent to the tool if it is running.
- **Removing a tool** deletes the app's copy. What the tool saved is deleted
  too when the person picks that, unless the tool's program will not stop:
  then it is kept, and the person is told so and where it is. A folder that
  cannot be deleted, such as one the tool made read-only, is left, and the
  person is told that too. The tool's preferences go only together with
  the folder of what it saved: while that folder is kept, so are they.

For the two Swift samples, build their folders first:

```sh
bazel build --config=macos-app //packages/vitruvian-sdk:sample-folders
```

They are then in `bazel-bin/packages/vitruvian-sdk/built/`.

## Finding out why it does not work

Start with the command line. Neither command needs the app.

```sh
vitruvian-tool validate ~/my-tool
vitruvian-tool run ~/my-tool --command hello
vitruvian-tool run ~/my-tool --command hello --refuse
vitruvian-tool run ~/my-tool --command hello --app-path
```

- `validate` says what the app would refuse the folder for, every problem at
  once, the app's own reason first. It exits with 0 for a folder the app
  would take, 1 for one it would refuse, and 2 when it could not read what
  you typed. A pass ends by saying what it cannot promise:

  ```text
  This is what the app checks before it asks the person. It cannot promise the rest: an older app may not know a service or a surface this one does; the app refuses an id another tool already has, and a folder inside its own support folder; and nothing here started the program.
  ```

- `run` starts the tool and prints everything it asks for. It answers each
  request as done and **does nothing on your Mac**: no message is shown, no
  link opened, nothing pasted or pressed, no process ended, and the clipboard
  it reads and writes is its own, not yours. It gives the tool a folder of its
  own and deletes it afterwards. Control-C ends the tool. However the run
  ends, a program the tool started is ended with it, as in the app.
- `run` is one run, not the app. It grants every service the manifest lists,
  where the app may refuse one at any time. It does not stop an idle tool,
  does not start a crashed one again, and does not count lines a second. A
  tool that passes here can still be stopped by the app for those.
- `--refuse` refuses every request, to see that your commands still answer.
- `--app-path` starts the tool with the short `PATH` the app has. Use it when
  the tool works in a terminal and not in the app.
- `python3 conformance/conformance.py <folder>`, in `packages/vitruvian-sdk`,
  runs seven scripted checks and exits with 0 when they pass. It needs Python
  and nothing else.

In the app, open the tool's row in Settings. The detail view shows the tool's
log: what it wrote to standard error, what it sent as `log`, and what the app
noted about it. It shows the newest 200 lines as they were when the view was
opened; close it and open it again to see more.

## What a tool must not assume

- **Not the `PATH` of a terminal.** The app starts a tool with the
  environment the app has. Opened from the Finder, that is the short `PATH`
  macOS gives an app: `/usr/bin:/bin:/usr/sbin:/sbin`. A first line of
  `#!/usr/bin/env node` finds nothing there, which is why the TypeScript
  template starts Node from `bin/tool`. `#!/usr/bin/env python3` finds
  `/usr/bin/python3`, which is Apple's and is there only once the Command
  Line Tools are installed; it does not find a Python from Homebrew, or the
  packages installed for one. Name the interpreter by its full path, or ship
  it, or put what it needs inside the tool's folder, as the Python kit
  template puts the kit in `lib/`. `vitruvian-tool run --app-path` shows what
  the app will find.
- **Not that a request succeeds.** Any one can be refused.
- **Not that standard output is yours.** One stray `print` is a line that is
  not a message.
- **Not where it runs.** It is started in its data folder, not its own. Find
  your own files from the program's path, not from the current folder.
- **Not that it is alone.** After an update, the new program may start while
  the old one is still leaving.
- **Not that it keeps running.** An `onCommand` tool is stopped after two
  minutes with nothing asked of it. Keep what matters in a preference or in
  the data folder.
- **Not that a program it starts outlives it.** Whatever your tool starts
  is ended with it, however the tool ends: at goodbye, when it is removed
  or switched off, when the app quits, after two idle minutes, and when it
  crashes. The app does that by the tool's process group, which a program
  you start is in unless it leaves: Python's `subprocess`, Node's
  `child_process` and a shell's `&` all stay in it. A program that must
  outlive the tool has to leave the group, with a new session
  (`start_new_session=True`, `detached: true`, `setsid`), and is then
  yours to end. Foundation's `Process`, in a Swift tool, puts each program
  it starts in a group of its own, so the app does not reach those: end
  them yourself. Nothing is ended if the app itself crashes: your tool
  still ends when its input closes, and should take its helpers with it.
- **Not that the data folder outlives it.** Removing the tool may delete it.
- **Not a permission.** A tool has what Vitruvian has, and nothing more. A
  prompt your tool causes says Vitruvian is asking. Vitruvian's permissions
  reset when the app is updated, and the tool's with them.
- **Not a shortcut of its own.** Give a command the `shortcut` surface and
  let the person record one, so the app can check it against every other.
- **Not that the person sees every preference.** Only one with a `title` is
  shown, in the tool's detail in Settings, and can be changed there. One
  without is a value your tool keeps with `storage/set`, and yours alone.
- **Not that a preference is as you left it.** The person may change a titled
  one at any time, also while your tool is not running. Read it when you
  need it, or hear `preferences/changed`.
- **Not that the language stays.** The person may change it while your
  tool runs. Hear `language/changed`, or read `app.language` each time you
  need it. An older app never sends the notice.
- **Not that its last words arrive.** A final line with no line break at its
  end is dropped.
- **Not an argument.** A command is run by its id, with nothing else.
{% endraw %}
