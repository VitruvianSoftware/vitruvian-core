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
    let next = (try app.value("count").numberValue ?? 0) + 1
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
    counted = app.storage.get(key="count").value + 1
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
| `protocol` | yes | `"1"`. |
| `publisher` | yes | Who made it. Shown beside the name. |
| `license` | no | Text. Not shown yet. |
| `icon` | no | An SF Symbol name. One the Mac does not have, or none, draws as a puzzle piece. |
| `uses` | no | The app services the tool calls: `notify`, `open`, `clipboard.read`, `clipboard.write`, `keystrokes`, `processes`, `storage`. A request for a service that is not listed is refused. **It is not a list of what the tool may do**: a tool may do anything. |
| `contributes` | no | Holds `commands`: at most 32. Each has an `id`, a `title` (a map of languages), an optional `icon`, and `surfaces`: where it is offered, any of `commandBar`, `radial`, `quickPanel`, `shortcut`. |
| `preferences` | no | At most 16 values the app keeps for the tool. Each is `{ id, title, type, default }`; `type` is `string`, `boolean`, `integer` or `number`, and the default is of that type. `title` may be left out. It is what the setting is called to the person: a map of languages, like `name`, of at most 60 characters each, with no line break. A preference with a title is shown in the tool's detail in Settings, where the person can change it: a switch for `boolean`, a text field for `string`, a number field for `integer` and `number`. A preference with no title is the tool's alone and is never shown to the person. The tool reads and writes any of them with `storage/get` and `storage/set`. |
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
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en-US","dataFolder":"/Users/you/Library/Application Support/com.vitruviansoftware.vitruvian/ToolData/com.acme.deploys"}}
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","toolVersion":"1.2.0"}}
```

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
  runs five scripted checks and exits with 0 when they pass. It needs Python
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
