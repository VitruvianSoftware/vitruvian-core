<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Vitruvian Courier milestone 6: acceptance list

Milestone 6 is done when Google Messages has moved to Vitruvian Courier, Beeper is logged out, and Vitruvian Courier has shipped as a release through the desktop pipeline. Tick a line when you have seen it work. Write down anything wrong, with no names, numbers or message text.

A tick means "I saw this work", not "the code exists". The plan is `docs/superpowers/plans/2026-11-02-courier-m6-cutover-and-release.md`; the steps are in [cutover.md](cutover.md).

## Before the first release

- [ ] The `vitruvian-courier-release` GitHub Environment exists (Settings ▸ Environments), and its deployment branches are `main` and `vitruvian-courier-v*` tags only.
- [ ] It has the secrets `COURIER_TELEGRAM_API_ID` and `COURIER_TELEGRAM_API_HASH` (`bazel run //tools/sync-env-secrets:apply -- vitruvian-courier-release`), with the same values as the secret store the local install reads. Without them the release job stops before building, by design.
- [ ] The Vitruvian Courier release PR ("chore(main): release vitruvian-courier …") opened after this milestone's PR merged. If you want to look at it before it ships, hold it (`bazel run //tools/agent-app -- pr-hold <pr#>`); otherwise it merges itself on green CI.

## The release

- [ ] The `vitruvian-courier-release` run for the release finished green, including "Check the release has every file".
- [ ] The release `vitruvian-courier-v<version>` has five files and their `.sha256`: `VitruvianCourier-<version>-universal.dmg`, `VitruvianCourier-<version>.dmg`, `-arm64.dmg`, `-x86_64.dmg` and `-universal.zip`.
- [ ] `brew info --cask vitruviansoftware/tap/vitruvian-courier` shows the new version. Homebrew 7 will not read an untrusted tap, so on a Mac that has not trusted ours, run `brew tap vitruviansoftware/tap && brew trust vitruviansoftware/tap` first.
- [ ] On a Mac with the previous version from Homebrew, `brew upgrade --cask vitruviansoftware/tap/vitruvian-courier` installs the new one. If it says nothing is outdated, the tap is not trusted: `brew trust vitruviansoftware/tap`, then upgrade again.
- [ ] The downloaded DMG opens with no "unidentified developer" or "can't be checked" warning, and Vitruvian Courier opens from it with none either.
- [ ] In Terminal, `spctl -a -vv /Applications/Vitruvian Courier.app` says "accepted" and "source=Notarized Developer ID".
- [ ] `codesign -dv /Applications/Vitruvian Courier.app/Contents/Helpers/vitruvian-courier-engine` names the Developer ID and shows `flags=0x10000(runtime)`.
- [ ] `lipo -archs /Applications/Vitruvian Courier.app/Contents/Helpers/vitruvian-courier-engine` prints both `x86_64` and `arm64`.
- [ ] Settings ▸ About shows the release's version.

## Install over the old build

- [ ] Installing the release over the build from `:install` keeps every chat, account and setting.
- [ ] Keychain: at most one prompt to allow Vitruvian Courier, and none after choosing Always Allow.
- [ ] Telegram works without asking for developer keys (the release has Vitruvian Courier's Telegram app ID).
- [ ] Contacts and Calendar permissions still work (the release keeps the entitlements for them).
- [ ] Vitruvian Courier still starts at login, if it did before.

## Google Messages

- [ ] Unpairing Beeper on the phone (Device pairing) removes it from the list.
- [ ] Add Account ▸ Google Messages shows the one-web-session note before it starts.
- [ ] Pairing by QR code works; conversations appear; a new SMS and a new RCS message arrive within a minute, with a notification.
- [ ] A reply from Vitruvian Courier arrives on the other person's phone.

## Every network

- [ ] WhatsApp receives and sends.
- [ ] Signal receives and sends.
- [ ] Telegram receives and sends.
- [ ] Slack receives and sends.
- [ ] Google Messages receives and sends.
- [ ] Google Chat receives and sends.

## Claude Code

- [ ] After `claude mcp add … beeper http://127.0.0.1:23390/v0/mcp …`, a new session's `/mcp` shows `beeper` connected.
- [ ] `get_accounts` lists all six networks.
- [ ] `search_messages` finds a word you know is there.
- [ ] With "Can send messages" on, `send_message` sends; with it off, it is refused.
- [ ] Nothing in `~/.claude.json` still points at port 23373.

## Beeper logged out

- [ ] Beeper is logged out and quit, and no longer in Login Items.
- [ ] A day later, every network still receives in Vitruvian Courier.

## Going back (try once, before logging out of Beeper)

- [ ] `cp ~/.claude.json.before-courier ~/.claude.json` puts Claude Code back on Beeper, and a new session works with it.
- [ ] Putting it back on Vitruvian Courier again works the same way.
