# The GitHub tool

Your pull requests and the checks on `main`, in the Vitruvian app's Dynamic
Island, and on a GravaStar mouse's light. A tool from outside, written to
protocol 2 with the Swift kit: the app draws its pages; the tool polls
GitHub, signs you in and drives the mouse.

It took over from the app's own GitHub feature (Vitruvian 3.46 offers it;
3.47 removes the feature). The code came with it, which is why this folder is
GPL-3.0-or-later like the app, not MIT like the kit it links.

## Get it

In the app: the Vitruvian catalog on Settings › Extensions, GitHub,
Install. The app verifies the download against the signed catalog and shows
the same agreement sheet as for any tool. Nothing here is audited by that:
the tool runs as you, with every permission the app has.

By hand: the zip on a [release](https://github.com/VitruvianSoftware/vitruvian-tool-github/releases),
unpacked anywhere, then Add from Folder… on Settings › Extensions.

## What it does

- **In the island**, in the Explore gallery, a section "GitHub": each watched
  repository with the colour of its `main` (green, amber, red, grey), what
  passed, failed and runs, and its branch and head (`main · a1b2c3d`); the
  merge queue of the repository in view, every entry in queue order with
  where it stands; then the pull requests you wrote or were asked to
  review, each with its checks' colour and its review standing. A tap on a
  repository opens its branch's check list (failing first, then running,
  then passed, then the rest) and its merge queue; a tap on a pull request
  opens its check list and its merge-queue standing. On either, a tap on
  the header opens it on GitHub (a repository's Actions page), a tap on a
  check opens the check, and "Back" returns to the list. With more than one
  repository watched, from Vitruvian 3.48, a menu picks the repository in
  view. "Refresh" asks GitHub now; "Open in GitHub" opens the repository in
  view; "Re-run failed checks" re-runs the failed jobs of `main`'s workflow
  runs. Under them, the time GitHub was last read. The section's badge
  counts what is red.
- **On the closed island**, from Vitruvian 3.48: a small mark after the
  agent mark, as the app's own GitHub feature drew it. A tick when
  everything is green, the branch glyph while checks run, a red mark when
  one failed, and a raised hand while a check waits for approval, which
  outranks every colour, as on the mouse. Nothing while you are signed out
  or nothing has been read yet. The app's switch in the tool's detail hides
  it; an older app shows no mark.
  From Vitruvian 3.50, while checks run, the number running across your
  watched repositories shows beside the mark, in place of the percent:
  "3", or "99+" above 99. Every other state shows no number. Vitruvian
  3.48 and 3.49 show the mark without it.
- **In Settings**, in the tool's detail: the account (sign in with the
  GitHub CLI's login, a token, or a code; sign out; a link makes a token on
  GitHub with the scopes the tool reads, `repo`, `workflow` and `read:org`;
  "Copy" puts a sign-in code on the clipboard), a button for each mouse
  light, to try it now, when a mouse command is found and the mouse shows
  the status, and below it the
  settings the app draws for the tool: the watched repositories, the two
  poll intervals, and the mouse's command, colours and styles. From
  Vitruvian 3.48 each of the five mouse lights is a menu: the ten colours,
  solid or pulsing, and "Restore my lighting" or "Turn the light off" when
  nothing is watched. A value you typed before, such as `breathe blue 5`,
  is shown as written at the top of its menu and keeps working until you
  pick another. An older app draws them as text fields, as before.
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

Vitruvian 3.46 to 3.50.1 hand this tool what the app's old GitHub feature
kept, once, through the tool's `storage`, when the tool is added: the token,
the watched repositories, the poll intervals, the mouse settings and the
client ID. The tool moves the token into `secrets.json` on its first run and
clears the handed copy. The feature itself went in 3.49; the hand-off went
after 3.50.1. Added with a later app, the tool starts signed out, with its
own defaults: sign in once. The feature's `h` key did not move: from
Vitruvian 3.51 the tool's page is a section in the island's Explore gallery
(on 3.46 to 3.50.2, a tile on the island's Tools page).

## Build

In vitruvian-core: `bazel build --config=macos-app //apps/desktop/vitruvian-tool-github:tool-folder`
leaves the tool's folder, with `vitruvian-tool.json` and `bin/tool`, under
`bazel-bin/apps/desktop/vitruvian-tool-github/built/github/`. Tests:
`bazel test --config=macos-app //apps/desktop/vitruvian-tool-github/...`.

Here, in the mirror: `swift build -c release` against the published kit, as
`release.yml` does; the release attaches `github-tool-X.Y.Z.zip` and its
SHA-256, which the catalog entry pins.
