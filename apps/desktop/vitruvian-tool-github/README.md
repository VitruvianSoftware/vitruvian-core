# The GitHub tool

Your pull requests and the checks on `main`, in the Vitruvian app's Dynamic
Island, and on a GravaStar mouse's light. A tool from outside, written to
protocol 2 with the Swift kit: the app draws its pages; the tool polls
GitHub, signs you in and drives the mouse.

It took over from the app's own GitHub feature (Vitruvian 3.46 offers it;
3.47 removes the feature). The code came with it, which is why this folder is
GPL-3.0-or-later like the app, not MIT like the kit it links.

## Get it

In the app: Settings, Features, Tools from outside, Browse Tools…, GitHub,
Install. The app verifies the download against the signed catalog and shows
the same agreement sheet as for any tool. Nothing here is audited by that:
the tool runs as you, with every permission the app has.

By hand: the zip on a [release](https://github.com/VitruvianSoftware/vitruvian-tool-github/releases),
unpacked anywhere, then Add a Tool… in the same place.

## What it does

- **In the island**, on the Tools page, a tile "GitHub": each watched
  repository with the colour of its `main` (green, amber, red, grey) and
  what passed, failed and runs; then the pull requests you wrote or were
  asked to review, each with its checks' colour and its review standing. A
  tap opens the pull request. "Refresh" asks GitHub now; "Re-run failed
  checks" re-runs the failed jobs of `main`'s workflow runs. The tile's
  badge counts what is red.
- **In Settings**, in the tool's detail: the account (sign in with the
  GitHub CLI's login, a token, or a code; sign out), and below it the
  settings the app draws for the tool: the watched repositories, the two
  poll intervals, and the mouse's command, colours and styles.
- **The mouse**: with "Show status on the GravaStar mouse" on, the light
  follows the colour of everything together, and a check waiting for
  approval outranks it. The command is found as the app's feature found it:
  the path you set, the app's own copy, PATH, `~/.local/bin`, Homebrew.

Signing in through a browser window does not exist here: a custom URL
scheme belongs to an app, and the relay that redeemed the code is gone. The
GitHub CLI's login (`gh auth login`), a token, or a code (the device flow,
which needs the GitHub App's client ID under its setting) are the three ways
in. The token is kept in `secrets.json`, readable by you alone, in the folder
the app gives the tool, never in the Keychain: a program signed ad hoc is a
new program to the Keychain with every release.

## From the app's feature

When the app installs this tool from the catalog while its GitHub feature is
on, it hands over, once, through the tool's `storage`: the token, the
watched repositories, the poll intervals, the mouse settings and the client
ID, and turns the feature off. The tool moves the token into `secrets.json`
on its first run and clears the handed copy. The feature's island page, its
place in your island layout and its `h` key do not move: the tool's page is
a tile on the island's Tools page.

## Build

In vitruvian-core: `bazel build --config=macos-app //apps/desktop/vitruvian-tool-github:tool-folder`
leaves the tool's folder, with `vitruvian-tool.json` and `bin/tool`, under
`bazel-bin/apps/desktop/vitruvian-tool-github/built/github/`. Tests:
`bazel test --config=macos-app //apps/desktop/vitruvian-tool-github/...`.

Here, in the mirror: `swift build -c release` against the published kit, as
`release.yml` does; the release attaches `github-tool-X.Y.Z.zip` and its
SHA-256, which the catalog entry pins.
