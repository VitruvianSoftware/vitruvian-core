---
layout: tools
title: "The Vitruvian tool protocol, versions 1 and 2"
description: "How Vitruvian and a tool talk: one JSON message per line over the tool's standard input and output."
permalink: /tools/protocol/
source: packages/vitruvian-sdk/protocol/README.md
---
{%- comment -%}
  Written by tools/sync-site-tools/sync.py from packages/vitruvian-sdk.
  Do not edit it: change the source, then run
    bazel run //tools/sync-site-tools:sync
{%- endcomment -%}
{% raw %}
A tool is a program the Vitruvian app starts and talks to. This folder says
how they talk. It is the source of truth: the Swift types in
`../Sources/VitruvianToolProtocol` and the script in `../conformance` are
written to match it, and tests fail when they stop matching.

| File | What it is |
|---|---|
| `manifest.schema.json` | `vitruvian-tool.json`, the file at the top of a tool's folder |
| `messages.schema.json` | one message, and what each message carries |
| `methods.json` | every message: who sends it, whether it is answered, what it needs |
| `examples/` | manifests and messages, valid and not, that both sides are tested against; and `folders.json`, folders the app and `vitruvian-tool validate` must judge alike |

Every field has a description in its schema. This page is the overview.

## The link

The app starts the tool's program in a folder the tool may keep files in. The
program's standard input and standard output are the link. Its standard error
is its log.

- One message per line, in UTF-8. A line ends with a line break (`\n`) and
  has none inside it. JSON never needs one: inside a string it is written `\n`.
- A line is at most 1,048,576 bytes, not counting its line break.
- An empty line is ignored. Anything else that is not a message is an error.
- A last line with no line break is never delivered: the reader holds it until
  its line break comes, so end every message with one.
- Lines end with `\n` alone. With `\r\n` the `\r` stays in the line and counts
  toward the 1,048,576 bytes.
- The tool's standard output carries nothing but messages. Print to standard
  error instead.

## A message

A message is JSON-RPC 2.0. There are four kinds.

```json
{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"copyLatest"}}
{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["copyLatest"]}}
{"jsonrpc":"2.0","id":2,"result":{}}
{"jsonrpc":"2.0","id":2,"error":{"code":-32010,"message":"command refused"}}
```

- A **request** has an `id` and is answered, with a **result** or a
  **failure** that carries the same `id`.
- A **notice** has no `id` and is not answered.
- An `id` is a whole number or a string. Whoever sends the request picks it.
- `params` is always an object. A message that carries nothing leaves it out.
- A request that was simply done is answered with `{}`.
- A field you do not know is ignored. That is how a later version adds one.
  A request you do not know is answered with failure -32601. A notice you do
  not know is ignored.

## What the app sends

| Message | Kind | Meaning |
|---|---|---|
| `initialize` | request | The first message. It carries the protocol versions the app speaks, the language in use and the tool's data folder. The tool answers with the version it picked and its own version. Until it has, neither side sends anything else. |
| `command/run` | request | Run this command. `command` is the id the manifest gives it. Answer `{}` when it ran, or failure -32010 when you will not run it. |
| `preferences/changed` | notice | The person changed these preferences, in the tool's detail in Settings: each one's id and its new value. Sent only to a tool that is running and has answered `initialize`. |
| `language/changed` | notice | The person changed the app's language: the new one, as a tag. Sent only to a tool that is running and has answered `initialize`, once for each change. A tool that starts later learns the language from `initialize`. |
| `shutdown` | notice | Stop. The app then closes the tool's input. The tool exits with 0 within two seconds. |
| `ui/open` | request | Version 2. The person opened one of the tool's panels. A blocks panel is answered with its first page, `{ "tree": … }`; a web panel with `{}`. |
| `ui/event` | request | Version 2. The person acted in an open panel: `tap`, `toggle`, `submit`, `change`, or `bridge` for a web panel's page. Answered with the next page, `{ "keep": true }`, a `reply` for the page, or a window panel to `open`. |
| `ui/close` | notice | Version 2. The panel went away. |

## What a tool sends

A tool may do any of this itself. It is a separate program with everything the
app has. These messages are for what is better done through the app.

| Message | Kind | In `uses` | Meaning |
|---|---|---|---|
| `commands/state` | notice | | Which commands can run now. Send it whenever that changes. Until the first one, all of them can. |
| `notify/hud` | request | `notify` | Show the app's short on-screen message, with a symbol. |
| `notify/beep` | request | `notify` | The alert sound. |
| `open/url` | request | `open` | Open a link. |
| `clipboard/readText` | request | `clipboard.read` | The clipboard's text. |
| `clipboard/writeText` | request | `clipboard.write` | Replace the clipboard with this text, marked as Vitruvian's so clipboard history files it correctly. |
| `keystrokes/paste` | request | `keystrokes` | Paste this text into the app in front. |
| `keystrokes/pressMenuItem` | request | `keystrokes` | Press the menu item with one of these key equivalents in the app in front. |
| `processes/terminate` | request | `processes` | End this process, with the app's checks and its administrator prompt. |
| `storage/get`, `storage/set` | request | `storage` | Read or write one of the preferences the manifest declares. Text is at most 4,096 characters; a longer one is refused with -32602. |
| `log` | notice | | A line for the tool's log in Settings. |
| `ui/render` | notice | | Version 2. A new page for a panel that is open. |
| `ui/badge` | request | `notify` | Version 2. A count or a dot beside the tool's page in the island's Explore gallery. |

## Being refused

Any request can be refused. A refusal is a failure with one of these codes.

| Code | Who | Meaning |
|---|---|---|
| -32001 | app | The service is not listed in the tool's `uses`. `data.service` names it. |
| -32002 | app | The tool is not installed. |
| -32003 | app | Vitruvian lacks a macOS permission the service needs. `data.permission` names it. |
| -32004 | app | Not available right now. |
| -32010 | tool | The tool will not run the command. |

The other codes are JSON-RPC's own: -32700 not JSON, -32600 not a message,
-32601 unknown method, -32602 wrong params, -32603 something broke inside.

A failure's `message` is a few English words for a log. It is never shown to
the person as it is.

## The manifest

`vitruvian-tool.json` says what the tool is. `id`, `name`, `version`,
`protocol`, `publisher` and `runtime` are required.

- **The id has a dot** (`com.acme.deploys`) and is at most 128 characters.
- **Text is a map of languages**, `{ "en": "Deploys", "fr": "Déploiements" }`.
  English is required. It is shown as written.
- **`uses` lists the app services the tool calls.** It is not a list of what
  the tool is allowed to do.
- **A name the app does not know refuses the tool**: a service, a surface, a
  kind of preference, a way of starting. The reason names it.
- **`runtime.exec` stays inside the folder.**
- **A preference may carry a `title`**, text in several languages like any
  other. It is what the setting is called to the person. One with no title
  is the tool's alone, and the app never shows it. One with a title is
  listed in the tool's detail in Settings, where the person can change it.
  The field was added
  after the first version 1, with no new version: an app from before it
  ignores it, and shows no setting.
- **Limits**: the file 65,536 bytes, 32 commands, 16 preferences, a
  preference's title 60 characters in each language with no control
  character, and text saved with `storage/set` 4,096 characters. A
  character here is a Unicode code point, as JSON Schema counts.

## Version 2: a tool that draws

A manifest that says `"protocol": "2"` may list `contributes.panels`: each
has an `id`, a `title`, a `placement` (`island`, `settings` or `window`), an
optional `icon`, and a `kind`. A `blocks` panel, the default, is drawn by the
app from a page the tool sends. A `web` panel is a page from the tool's own
folder, named by `entry`.

- **At most 8 panels**, one in the island and one in Settings at most.
- **A page is a list of blocks**, of thirteen kinds: `text`, `heading`, `row`,
  `button`, `toggle`, `field`, `list`, `progress`, `image`, `divider`,
  `link`, `spacer`, `choice`. Each kind's fields are in `messages.schema.json`. A block
  of a kind the app does not know is drawn as its `fallback`, or left out.
- **Limits**: a page is at most 262,144 bytes as JSON, an image written into
  it included, and at most 200 blocks; a list at most 200 rows. The app draws
  at most four `ui/render` a second for each panel, the last of the ones
  between; more than forty in one second is a flood, and the tool is
  stopped.
- **A web panel** loads only files from the tool's folder. Its page reaches
  the app through `window.vitruvian.call(method, params)`, which the app
  passes to the tool's program as `ui/event` with `event: "bridge"`; the
  tool does the request, under its own `uses`, and its answer's `reply` is
  what the page gets back. `window.vitruvian.on(name, handler)` hears
  `preferences/changed` and `language/changed`, with the params the tool is
  sent; `window.vitruvian.language` and
  `window.vitruvian.appearance` are set before the page's scripts run.
- **An app that speaks only version 1** refuses a manifest that says 2
  (`unsupportedProtocol`). **An app of version 2 runs a version 1 tool as
  it always did**: it offers both versions at `initialize`, and the tool
  picks.

The smallest tool of each version is in the SDK's `conformance/` folder, in
plain Python with nothing else. `reference-tool` speaks version 1.
`reference-tool-2` is the same tool with one panel, a line of text and a
button: it answers `ui/open` with a page, and answers the button's `ui/event`
with the next one.

## Added to version 2 without a new version

Vitruvian 3.48 added four things to version 2. An older app ignores each
key and answers the one new request with failure -32601, so a tool that
uses them still installs and runs there.

- **`features` in `initialize`**: the names of what this app has beyond the
  first release of the version: `ui.status`, `ui.choice`,
  `preferences.options`. An app before 3.48 sends none. A tool asks before
  it uses one, and ignores a name it does not know.
- **A status, `ui/status`**: a request from the tool, with a `state` of
  `none`, `ok`, `busy`, `attention` or `failure`, an optional `text` and an
  optional `icon`. The app draws it as a small mark on the closed island.
  The manifest declares it, as `contributes.status` with a `placement` of
  `island`, in protocol 2 only; it needs nothing in `uses`. One from a tool
  that did not declare it is answered with failure -32602. Each replaces
  the last, and it goes when the tool's program ends.
- **A `choice` block**: a pop-up menu of 1 to 64 options, each a `value` and
  a `title`, with the selected `value`. Picking one is the event `change`,
  with the option's value. An app before 3.48 draws its `fallback`.
- **`options` on a `string` preference**: 1 to 64 of a `value` and a `title`
  in several languages. The app draws a pop-up menu in place of a text
  field. They are how the app draws, not a rule on the value: a saved value
  that is no option's is kept. An app before 3.48 draws a text field.

A list of choices is never a new preference `type`: every app refuses a
manifest with a type it does not know.

Vitruvian 3.50 added a status's words, in the same way. 3.48 and 3.49 read
each new field and key and ignore it, so the mark is still drawn there.

- **`activity` and `since` on `ui/status`**: a few words for the closed
  island (`activity`, text in one or more languages), or a start time in
  Unix seconds the app counts the seconds from (`since`, a number of at
  least 0). The words win over the start time. The app draws them beside
  the mark, in place of the allowance percent, while it is the mark shown.
  A `since` below 0 or not a number is answered with failure -32602.
- **`activity` in `contributes.status`**: `true` says the status may carry
  words. Words from a tool that did not say so are left out, the mark is
  drawn, and the answer is `{}`.
- **`ui.status.activity` in `features`**: the app draws them. Each kit sends
  the two fields only to an app that names it.

Vitruvian 3.58 lets a tool open its own settings, with no new field and no
new version: only what the app does with `open` changed.

- **`open` in the answer to `ui/event` may name the tool's settings panel**:
  the app brings Settings to the front on the tool's detail, where that
  panel is drawn. The id is looked up in the asking tool's own manifest, so
  a tool can open only its own; an id the manifest does not declare, or one
  of an island panel, opens nothing, and the tool's log says so.
- **`ui.open.settings` in `features`**: the app does this. A tool asks before
  it offers the button. An app before 3.58 opens nothing for such an answer,
  writes a line in the tool's log, and still draws a `tree` sent with it.

## Changing the protocol

A new message or field needs no new version when an old tool or an old app can
ignore it. Anything an old one would misread needs a new version, as panels
did.

A change is three things in one commit: the schema, the Swift type, and an
example in `examples/`. The tests hold the three together, and they can only
see a difference an example crosses.

## Every message, from `methods.json`

| Message | Sent by | Kind | In `uses` |
|---|---|---|---|
| `initialize` | app | request |  |
| `command/run` | app | request |  |
| `preferences/changed` | app | notice |  |
| `language/changed` | app | notice |  |
| `shutdown` | app | notice |  |
| `commands/state` | tool | notice |  |
| `notify/hud` | tool | request | `notify` |
| `notify/beep` | tool | request | `notify` |
| `open/url` | tool | request | `open` |
| `clipboard/readText` | tool | request | `clipboard.read` |
| `clipboard/writeText` | tool | request | `clipboard.write` |
| `keystrokes/paste` | tool | request | `keystrokes` |
| `keystrokes/pressMenuItem` | tool | request | `keystrokes` |
| `processes/terminate` | tool | request | `processes` |
| `storage/get` | tool | request | `storage` |
| `storage/set` | tool | request | `storage` |
| `log` | tool | notice |  |
| `ui/open` | app | request |  |
| `ui/event` | app | request |  |
| `ui/close` | app | notice |  |
| `ui/render` | tool | notice |  |
| `ui/badge` | tool | request | `notify` |
| `ui/status` | tool | request |  |
{% endraw %}
