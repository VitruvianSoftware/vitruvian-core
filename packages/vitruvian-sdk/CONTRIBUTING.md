# Contributing to the Vitruvian SDK

Thank you for wanting to help. This page says where a change goes, what a
change to the protocol must touch, and how a release is made.

## Where a change goes

The SDK is developed in the
[vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core)
repository, in `packages/vitruvian-sdk`. The
[vitruvian-sdk](https://github.com/VitruvianSoftware/vitruvian-sdk)
repository is a copy of that folder, made on every change. It takes no pull
requests: one opened there is not merged, because the next copy would
overwrite it.

1. **Open an issue** on
   [vitruvian-sdk](https://github.com/VitruvianSoftware/vitruvian-sdk/issues).
   Say what you want a tool to be able to do, and why. For a change to the
   protocol, say what an older app or an older tool would do with it.
2. **Open a pull request** to vitruvian-core, changing files under
   `packages/vitruvian-sdk`. Link the issue.

Everything in this folder is MIT licensed, and a contribution is too. The
Vitruvian app, which links the protocol's Swift types, is GPL-3.0-or-later:
nothing from the app's folder may be copied here.

## A change to the protocol

The protocol is written down once, in `protocol/`, and four other places
must agree with it. A change touches all of them in one pull request, and
the tests refuse anything less.

| What | Where | The test that holds it |
|---|---|---|
| The schema | `protocol/manifest.schema.json`, `protocol/messages.schema.json`, `protocol/methods.json` | `protocol_examples_test` |
| The Swift types | `Sources/VitruvianToolProtocol` | `VitruvianToolProtocolTests` |
| An example | `protocol/examples/` | both of the above: they can only see a difference an example crosses |
| The kits in other languages | `kits/`, their types generated from the schema | none yet: the kits and their generator arrive in the next release, with a test that fails when the generated types are stale |
| The app's pin | `apps/desktop/vitruvian/bazel/tool_protocol.sha256` in vitruvian-core, written by `bazel run //apps/desktop/vitruvian:pin_tool_protocol` | `tool_protocol_pin_test`, in the app's folder |

**Additive within a version.** A new message or field needs no new version
when an older tool or an older app can ignore it: a field nobody knows is
ignored, a notice nobody knows is ignored, and a request nobody knows is
answered with failure -32601.

**Anything an older side would misread is a new version.** A tool's
manifest names one `protocol`, and the app refuses a manifest whose version it
does not speak. So a new version is added beside the old one, never in its
place: the app keeps speaking the old version for at least two minor releases
of the app after the new one ships.

`protocol/README.md` is the overview of the protocol as it is.

## Checking a change

In vitruvian-core, from its root:

```sh
bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests //packages/vitruvian-sdk:VitruvianToolKitTests //packages/vitruvian-sdk:VitruvianToolCLITests //packages/vitruvian-sdk:swift_samples_test //packages/vitruvian-sdk:init_test //packages/vitruvian-sdk:swift_template_test
bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test //packages/vitruvian-sdk:samples_test //packages/vitruvian-sdk:templates_in_sync_test //packages/vitruvian-sdk:guide_test //packages/vitruvian-sdk:release_version_test //packages/vitruvian-sdk:mirror_workflows_test //tools/sync-site-tools:in_sync_test
```

The first line needs a Mac with Xcode. The second runs anywhere with bash,
git and jq.

In a clone of vitruvian-sdk there is no Bazel. Its own CI runs `swift build`,
`swift test`, the conformance script on every sample, and the checks of the
examples and the templates, in `.github/workflows/ci.yml`. The same
commands work on your Mac. `docs/guide_test.py` runs only in vitruvian-core.

After changing `samples/hello-python` or `samples/hello-swift`, run
`bazel run //packages/vitruvian-sdk:sync-templates` and commit what it
writes: `vitruvian-tool init` holds a copy of each.

After changing `docs/writing-a-tool.md`, `protocol/README.md`,
`protocol/methods.json` or a hello sample, run
`bazel run //tools/sync-site-tools:sync` and commit what it writes:
vitruviansoftware.dev/tools holds a copy of each, and
`//tools/sync-site-tools:in_sync_test` fails until the copy matches.

## Releases

One version for the whole SDK. release-please keeps it, in vitruvian-core:

- A pull request whose title starts `feat(vitruvian-sdk):` or
  `fix(vitruvian-sdk):` and that changes this folder makes the next release:
  `fix` the next patch, `feat` the next minor version. `chore(vitruvian-sdk):`
  makes none, and neither does a change to `.github/` alone. Until 1.0.0 a
  breaking change also moves only the minor version; 1.0.0 is chosen, not
  reached by accident.
- release-please opens the release pull request. It writes the version into
  `.release-please-manifest.json`, `CHANGELOG.md` and
  `Sources/VitruvianToolCLI/Words.swift`. Never change the version by hand.
- When it merges, the copy reaches vitruvian-sdk, whose `release.yml` tags
  `vX.Y.Z` (Swift) and `go/vX.Y.Z` (Go), builds `vitruvian-tool` for Apple
  silicon and Intel, attaches it and the source to a GitHub release, and
  writes the Homebrew formula.

## Listing a tool

There is no catalogue of tools yet. It is the third stage of the plan in
vitruvian-core,
[`docs/superpowers/specs/2026-10-12-vitruvian-tools-for-everyone-design.md`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/docs/superpowers/specs/2026-10-12-vitruvian-tools-for-everyone-design.md),
section 7. Listing will be a pull request that adds one entry, with a
checklist on this page. Until then a person adds a tool from its folder, in
Vitruvian's Settings, under Features, "Tools from outside".
