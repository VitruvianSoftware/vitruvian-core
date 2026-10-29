# Agent guide: apps/desktop/vitruvian-tool-github

This guide adds to the root `AGENTS.md` and to `apps/desktop/AGENTS.md` for
this subtree. The 6-point release artifact contract there is for app
bundles; this is a tool, and its one artifact is a zip (see "Releases").

## Hard rules

- **This directory is GPL-3.0-or-later**, like `apps/desktop/vitruvian`,
  because its code came from that app's GitHub feature. New files get
  `// SPDX-License-Identifier: GPL-3.0-or-later` and
  `// Copyright (C) 2026 VitruvianSoftware`. Never copy code from here into
  an MIT part of the repository; `//tools/license:verify` exempts this
  folder from the MIT header check, and nothing MIT may link `:GitHubToolCore`.
- **It links the kit, and nothing of the app.** `//packages/vitruvian-sdk:VitruvianToolKit`
  and `:VitruvianToolProtocol` are visible to this package for that; the
  dependency runs MIT into GPL and never back.
- **Never change the protocol here.** A thing the tool needs that the
  protocol lacks is a change to `packages/vitruvian-sdk` with its full path
  (`packages/vitruvian-sdk/CONTRIBUTING.md`).
- **`BUILD` and `Package.swift` mirror each other**, target for target. The
  monorepo builds with Bazel against the local kit; the mirror builds with
  `swift build` against the published kit, from the version `Package.swift`
  names. `version_test.py` holds the manifest's version, `Version.swift` and
  the kit version to each other.

## Shape

- `Sources/GitHubToolCore`: everything but the link. Pure where it can be:
  the models and colour rules (`Models.swift`), the watchlist, the secret
  store (a 0600 file), the mouse (`MouseCommand`, `MouseDriver`), the
  sign-in values (`Auth.swift`), the REST client over a `Transport`
  (`API.swift`), the words in fifteen languages (`Words.swift`), the pages
  (`Pages.swift`), and `GitHubTool`, which holds the state and takes a
  `Host` so the tests drive it without a process.
- `Sources/github-tool/main.swift`: the program. It builds a `Tool` from the
  kit, its two panels and three commands, and a timer that polls; nothing
  else. Keep it thin.
- `Tests/GitHubToolCoreTests`: XCTest, no network, no process: a transport
  that answers itself, a mouse that records, a host that records.
- The tool's words are its own, in `Words.swift`, keyed by the app's
  language tags with English first; `WordsTests` holds every key to all
  fifteen. The app draws them as written and never translates them.
- **It works on an app without the newer features.** Its catalog entry
  asks for Vitruvian 3.46.0, and keeps asking for it. The status
  on the closed island (`ui/status`, from 3.48) goes through the kit's
  `App.status`, which sends nothing to an app that did not name `ui.status`
  at hello; the busy count beside it (`activity`, from 3.50) the kit
  leaves out for an app that did not name `ui.status.activity`. The five
  mouse settings stay `"type": "string"` with `options`: an older app
  ignores the options and draws a text field. Never give a
  setting a new type, and never rewrite a stored value: `MouseTests` holds
  every option to what `MouseLight.parse` reads and to what the app's
  feature handed over (3.46 to 3.50.1): those values stay in people's
  storage. The island's repository picker is a `choice` (from 3.48), sent
  only when `Host.supports(.choice)`; an older app gets no picker, and
  each repository's own page (a tap on its row) still shows its merge
  queue.
- **The colour options' titles are English only.** Eighty options in
  fifteen languages would pass the 65,536 bytes every app allows a manifest;
  `MouseTests` keeps the file under three quarters of that.

## Building and testing

- `bazel test --config=macos-app //apps/desktop/vitruvian-tool-github/...`
  runs the tests, builds the tool's folder and puts it through the
  conformance script. Everything is `manual` and macOS-only; the pipeline
  unit `vitruvian-tool-github` runs it on the `xcode-27` lane.
- To try it in the app: build `:tool-folder`, then Add from Folder… on
  Settings › Extensions, and pick
  `bazel-bin/apps/desktop/vitruvian-tool-github/built/github`.
- `bazel run //packages/vitruvian-sdk:conformance -- bazel-bin/apps/desktop/vitruvian-tool-github/built/github`
  is what `:conformance_test` runs.

## Releases

`release-please` (component `vitruvian-tool-github`, tag
`vitruvian-tool-github-vX.Y.Z`) writes the version into
`.release-please-manifest.json`, `vitruvian-tool.json` and `Version.swift`.
Copybara exports this folder to `VitruvianSoftware/vitruvian-tool-github`,
whose own `release.yml` tags `vX.Y.Z`, builds the universal binary, zips the
tool's folder as `github-tool-X.Y.Z.zip` and attaches it with its `.sha256`.
The catalog entry (`catalog/tools.json`) pins that zip; listing a new
version is a pull request there, with the asset's size and checksum.
