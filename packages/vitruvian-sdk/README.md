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
sheet.

**To write a tool, read [`docs/writing-a-tool.md`](docs/writing-a-tool.md).**
It gets you from nothing to a working tool in ten minutes, and then covers
the manifest, every message, the limits, and how to find out why a tool does
not work.

| Folder | What it is |
|---|---|
| [`docs/`](docs/writing-a-tool.md) | The guide for a tool's author. Its examples are tested. |
| [`protocol/`](protocol/README.md) | The protocol, version 1: the manifest and every message as JSON Schema, a table of the messages (`methods.json`), and examples. The source of truth. |
| `samples/` | Seven tools: `hello-python`, in plain Python with nothing else; `hello-swift`, `hello-typescript`, `hello-python-kit`, `hello-go` and `hello-rust`, each written with its kit; `front-window`, which reads the title of the window in front by asking macOS itself. |
| `Sources/VitruvianToolKit` | A Swift library to write a tool with: declare commands, handle them, call the app. |
| `kits/` | The same, for TypeScript (`@vitruviansoftware/tool-kit`, npm) and Python (`vitruvian-tool-kit`, PyPI). Their types are written from the schemas by `//tools/sdk-codegen`, and a test fails when they are not what it writes. |
| `go/` | The same kit in Go, module `github.com/VitruvianSoftware/vitruvian-sdk/go`, package `toolkit`. Go 1.22 or later, standard library only. |
| `kits/rust` | The same kit in Rust, crate `vitruvian-tool-kit`. Rust 1.75 or later; `serde` and `serde_json`. |
| `Sources/vitruvian-tool` | A command: `init` starts a new tool from a sample, `validate` reads a folder the way the app will, `run` plays the app's side in a terminal. `Sources/VitruvianToolCLI` is what it is made of. |
| `Sources/VitruvianToolProtocol` | The protocol as Swift types: the messages, one message per line, the manifest file and its rules. The app links this module. |
| `conformance/` | A script that plays the app's side to your tool in five scripted checks, and the smallest tool that passes it. |
| `.github/workflows/` | The CI and the release of [VitruvianSoftware/vitruvian-sdk](https://github.com/VitruvianSoftware/vitruvian-sdk). They run only there. |

## Getting it

This folder is published, on every change, to
[VitruvianSoftware/vitruvian-sdk](https://github.com/VitruvianSoftware/vitruvian-sdk),
with a tagged release for each version.

- **The command, with Homebrew**, which builds it from source on your Mac:
  `brew install VitruvianSoftware/tap/vitruvian-tool`.
- **The command, downloaded**: `vitruvian-tool-X.Y.Z-macos.tar.gz` from a
  [release](https://github.com/VitruvianSoftware/vitruvian-sdk/releases), one
  program for Apple silicon and Intel, with its `.sha256`. It is signed ad
  hoc, not with an Apple Developer ID, so macOS will not open a copy a
  browser downloaded until you clear the mark once:
  `xattr -d com.apple.quarantine vitruvian-tool`. The guide says how, and why.
- **The Swift package**: `https://github.com/VitruvianSoftware/vitruvian-sdk`,
  by its version tags, with the products `VitruvianToolKit` and
  `VitruvianToolProtocol`. `vitruvian-tool init --template swift` writes a
  package that depends on it.
- **To read**: [vitruviansoftware.dev/tools](https://vitruviansoftware.dev/tools/),
  a copy of the guide, the protocol and the examples.

To change the SDK, or to see how a release is made: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## The command

```sh
bazel run --config=macos-app //packages/vitruvian-sdk:vitruvian-tool -- init ~/my-tool --id com.you.my-tool --name "My tool" --publisher "You"
bazel run --config=macos-app //packages/vitruvian-sdk:vitruvian-tool -- validate ~/my-tool
bazel run --config=macos-app //packages/vitruvian-sdk:vitruvian-tool -- run ~/my-tool
```

- **`init`** writes a new tool into a folder that is not there yet, or is
  empty, and nowhere else. It refuses a path that is a symbolic link, writes
  over nothing, and writes nothing when the app would refuse the id. `--template swift` writes
  a Swift package that uses the kit, from the published SDK at the version
  the command was built from; `--sdk packages/vitruvian-sdk` builds it
  against a checkout instead. `--template typescript` and
  `--template python-kit` write a tool that uses the TypeScript or the Python
  kit, at the version of this SDK.
- **`validate`** reads a folder the way the app does before it offers to add
  a tool, and says what the app would refuse it for. It starts nothing. The
  manifest's rules are the code the app itself links. The folder's rules (the program is
  in the folder and can be run, macOS has not quarantined it, the folder
  holds at most 256 MB and 10,000 things) are written again here, and
  `protocol/examples/folders.json` is tested from both sides to keep the two
  alike: 22 folders today. It cannot promise the rest: an older app may not
  know a service this one does, and the app refuses an id another tool
  already has, and a folder inside its own support folder.
- **`run`** starts the tool and prints what it asks for. It answers every
  request as done and does nothing on your Mac: nothing is shown, opened,
  copied, pasted, pressed or ended. No flag changes that. Every wait has a
  limit but the wait for you to type, and Control-C ends the tool. It is one
  run, not the app, and says so in its first line: every service the manifest
  lists is granted, and there is no idle stop, no restart after a crash and no
  flood count.

## The samples

`samples/hello-python` is a tool as it stands: add that folder to the app. A
Swift sample has to be built first:

```sh
bazel build --config=macos-app //packages/vitruvian-sdk:sample-folders
```

That leaves `bazel-bin/packages/vitruvian-sdk/built/hello-swift` and
`built/front-window`, each with its manifest and `bin/tool`. Those are the
folders to add.

`hello-swift` declares one preference with a title, its count. Once the tool
is added, its detail in Settings lists "Counted so far" with a number field;
change it, run "Count one more", and the tool counts on from the new number
without being started again.

`front-window` needs the Accessibility permission of whoever starts it.
Started by Vitruvian, it has Vitruvian's. Nothing in this package asks for a
permission or grants one.

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
| shutdown | After `shutdown` and the end of its input, your tool exits with 0 within two seconds. What it wrote on the way out is read to the end, and each line must be a message. |

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

- **The params are checked against a table written by hand in the script**,
  not against the schemas. The schemas are the source of truth; if the two
  ever disagree, the schemas are right.
- **It does not check your manifest.** It reads the fields it needs from it.
  `protocol/manifest.schema.json` is what a manifest must satisfy.
- **It runs your first command only**, and has no check for a tool that
  floods the app or hangs outside an answer.
- **It has been proven against** the reference tool, the five samples, and
  twelve broken copies of the reference tool, each caught by the check meant
  for it.

## Working on the package

```sh
bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests //packages/vitruvian-sdk:VitruvianToolKitTests //packages/vitruvian-sdk:VitruvianToolCLITests //packages/vitruvian-sdk:swift_samples_test //packages/vitruvian-sdk:init_test //packages/vitruvian-sdk:swift_template_test
bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test //packages/vitruvian-sdk:samples_test //packages/vitruvian-sdk:templates_in_sync_test //packages/vitruvian-sdk:guide_test //packages/vitruvian-sdk:release_version_test //packages/vitruvian-sdk:mirror_workflows_test //tools/sync-site-tools:in_sync_test
bazel test //packages/vitruvian-sdk/go/toolkit:toolkit_test //packages/vitruvian-sdk/kits/rust:all //packages/vitruvian-sdk:go_kit_vet_test //packages/vitruvian-sdk:go_sample_test //packages/vitruvian-sdk:rust_sample_test //tools/sdk-codegen:in_sync_test
```

The third line runs anywhere too: the Go and Rust kits' tests, each the
Swift kit's tests ported; the Go kit through `go vet` as a module of its
own, which holds it to Go 1.22; the two samples, built, against the
conformance script; and the generated types against the schemas. The Go and
Rust kits' types are written by `bazel run //tools/sdk-codegen`: after a
change to `protocol/`, run it and commit what it writes.

Go commands for the Go kit outside Bazel: run them with `GOWORK=off` from
`go/`. In the repository's workspace they would rewrite `go.work.sum`.

The first line needs a Mac: the Swift types against the example files, the
kit against a link made of two files, the command against folders and real
processes, the two Swift samples against the conformance script, what
`init` writes, and the Swift tool `init` writes, built. The second runs anywhere: the example files against the
schemas, the conformance script against the reference tool, the Python sample,
the templates `init` holds against the samples they are copies of, every
example in the guide, the version in its three files, the mirror's workflows
(with bash, git and jq), and the website's copies of the guide, the protocol
and the samples. Together the first two tests keep the schemas and the
Swift types from drifting apart: see "Changing the protocol" in
[`protocol/README.md`](protocol/README.md).

After changing `samples/hello-python` or `samples/hello-swift`, run
`bazel run //packages/vitruvian-sdk:sync-templates`: `init` holds a copy of
each, and a test fails until the copy is the sample again.

`protocol/examples/folders.json` is read by this package's tests and by the
app's (`ToolFolderExamplesTests`). A rule about a tool's folder that changes
in the app changes there, and in `Sources/VitruvianToolCLI/FolderCheck.swift`.

On a Mac, building everything here also needs the flag:
`bazel build --config=macos-app //packages/vitruvian-sdk/...`.

`BUILD` and `Package.swift` describe the same targets and must be changed
together. CI builds with Bazel, with one exception: `swift_template_test`
starts a tool with `init --template swift`, runs the `build.sh` that wrote,
and holds `validate` and `run` to pass on the result. That is `swift build`
with the Mac's own Swift, against a copy of this package, so it builds the
kit and the protocol from `Package.swift` too. It builds no other target of
`Package.swift`. The mirror's own CI (`.github/workflows/ci.yml`) is what
runs `swift build` and `swift test` on every target, with the runner's
Xcode. Put through the conformance script, such a tool passed once, by hand
(Swift 6.4, 2026-10-12).

That test needs a Mac with Xcode and no network. It gives `swift build` a
home and a temporary folder of its own and deletes them. One thing it
cannot hold back: on Swift 6.4 a clean `swift build` leaves one empty
folder, `TemporaryDirectory.XXXXXX`, in the Mac's real temporary folder,
whatever the environment says. The test takes away the ones its own build
made: new since the test began, the test's user's, still for two seconds,
and holding nothing but an empty `.keep-directory`.

After changing a file under `Sources/VitruvianToolProtocol`, the Vitruvian app
must take the change too:
`bazel run //apps/desktop/vitruvian:pin_tool_protocol`, and a line in
`apps/desktop/vitruvian/UPSTREAM.md`. A test in the app's folder fails until
you do.

## Licence

MIT. See [`LICENSE`](LICENSE). The Vitruvian app that links this package is
GPL-3.0-or-later; nothing from the app's folder may be copied here.
