# vitruvian-sdk

What you build a Vitruvian tool against.

A tool is a separate program, in any language, that the Vitruvian desktop app
starts and talks to in JSON over the program's standard input and output. It
adds commands to the app: to the command bar, the radial menu, the Quick
panel, and as shortcuts.

**A tool is trusted like an app.** It runs as you, with every permission
Vitruvian has. The app does not limit or check what it does.

**The app adds a tool from a folder**, in Settings, under Features, in the
section "Tools from outside". The person picks the folder and agrees on one
sheet. This package is being built in stages, and the first is done. What is
here today:

| Folder | What it is |
|---|---|
| [`protocol/`](protocol/README.md) | The protocol, version 1: the manifest and every message as JSON Schema, a table of the messages (`methods.json`), and examples. The source of truth. Start here. |
| `Sources/VitruvianToolProtocol` | The same protocol as Swift types: the messages, one message per line, the manifest file and its rules. The app links this module. |
| `conformance/` | A script that plays the app's side to your tool, and the smallest tool that passes it. |

Not yet:

- A Swift library to write a tool with.
- A `vitruvian-tool` command.
- Samples, beyond the one reference tool.
- Publishing. The package is used from this repository and nowhere else.

## A tool, in short

A folder with a manifest and a program:

```
reference-tool/
  vitruvian-tool.json
  bin/reference_tool.py
```

`conformance/reference-tool` is exactly that: one Python file of under 100
lines, with no dependencies. Read it beside
[`protocol/README.md`](protocol/README.md).

## Checking a tool

```sh
python3 conformance/conformance.py path/to/your-tool
```

It needs Python 3 and nothing else, and it does not need the app. It starts
your tool's program in a folder of its own and checks five things, in order.
The first failure stops the run.

| Check | What must happen |
|---|---|
| handshake | Your tool answers `initialize` first, with version 1 and its own version. |
| a command | Your first command is run and answered. |
| unknown | A command you do not have is answered with a failure. |
| refusals | The command is run again with every request you make refused, and is still answered. |
| shutdown | After `shutdown` and the end of its input, your tool exits with 0 within two seconds. |

It exits with 0 when all five pass. Against the reference tool it prints:

```
ok       handshake: version 1, tool 0.1.0
ok       a command: hello: ran
ok       unknown: failure -32602
ok       refusals: 1 refused
ok       shutdown: exited with 0
```

While a command runs, the script answers your requests as the app would. A
service your manifest's `uses` does not list is refused with -32001.

Every line your tool writes must be one JSON-RPC 2.0 message of at most 1 MB.
The twelve messages a tool may send must each carry their own params, of the
right kind: a `notify/hud` with no `message` fails the run.

- `--via PROGRAM` starts your program through another one, for example
  `--via python3` for a script that is not executable.
- `--expect-refusal` fails unless something was refused. Use it when your
  command calls the app, to be sure the refusal path ran.

From this repository the same script is
`bazel run //packages/vitruvian-sdk:conformance -- path/to/your-tool`.

### What it does not check

Passing is not proof that the app will accept everything your tool does.

- **It does not read what your tool writes after its last answer.** A bad
  notice sent just before `shutdown` is not seen.
- **The params are checked against a table written by hand in the script**,
  not against the schemas. The schemas are the source of truth; if the two
  ever disagree, the schemas are right.
- **It does not check your manifest.** It reads the fields it needs from it.
  `protocol/manifest.schema.json` is what a manifest must satisfy.
- **It runs your first command only**, and has no check for a tool that
  floods the app or hangs outside an answer.
- **It has been proven against one tool**, the reference tool, and against
  ten broken copies of it, each caught by the check meant for it.

## Working on the package

```sh
bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests
bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test
```

The first needs a Mac. It checks the Swift types against the example files.
The second checks the same example files against the schemas, and the
conformance script against the reference tool. Together they keep the schemas
and the Swift types from drifting apart: see "Changing the protocol" in
[`protocol/README.md`](protocol/README.md).

On a Mac, building everything here also needs the flag:
`bazel build --config=macos-app //packages/vitruvian-sdk/...`.

`BUILD` and `Package.swift` describe the same targets and must be changed
together. CI builds with Bazel only. `Package.swift` was built once by hand
(`swift build`, Swift 6.4, 2026-10-10); its tests have not been run that way.

After changing a file under `Sources/VitruvianToolProtocol`, the Vitruvian app
must take the change too:
`bazel run //apps/desktop/vitruvian:pin_tool_protocol`, and a line in
`apps/desktop/vitruvian/UPSTREAM.md`. A test in the app's folder fails until
you do.

## Licence

MIT. See [`LICENSE`](LICENSE). The Vitruvian app that links this package is
GPL-3.0-or-later; nothing from the app's folder may be copied here.
