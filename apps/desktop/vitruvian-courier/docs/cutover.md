<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Moving from Beeper to Vitruvian Courier

This is the last step of milestone 6: Vitruvian Courier becomes the app you use, and Beeper is switched off. It takes about twenty minutes. Nothing here deletes any messages. Until the last step, you can stop and go back at any point (see [Going back](#going-back)).

You will need your phone (for Google Messages) and Terminal (for Claude Code).

## 1. Install the release

**Once, before the first release.** The release builds Vitruvian Courier's Telegram app ID into the app, from the `vitruvian-courier-release` GitHub Environment. Without it the release job stops. Fill it from the secret store, in Terminal at your checkout:

```sh
bazel run //tools/sync-env-secrets:unlock     # asks for your Bitwarden password
bazel run //tools/sync-env-secrets:bw-pull    # brings the store down
# Only if the two values are not in the vault yet (from my.telegram.org ▸ API development tools):
bazel run //tools/sync-env-secrets:set -- vitruvian-courier-release COURIER_TELEGRAM_API_ID
bazel run //tools/sync-env-secrets:set -- vitruvian-courier-release COURIER_TELEGRAM_API_HASH
bazel run //tools/sync-env-secrets:bw-push    # saves the store back to Bitwarden
bazel run //tools/sync-env-secrets:apply -- vitruvian-courier-release   # puts both into the environment
```

Use the values your installed Vitruvian Courier already has, so Telegram keeps working as it does now. The environment must exist first: it is created when the repo-config change in this milestone is applied.

1. Quit Vitruvian Courier if it is open (Vitruvian Courier ▸ Quit Vitruvian Courier, ⌘Q).
2. Download `VitruvianCourier-<version>-universal.dmg` from the newest `vitruvian-courier-v…` release on the [releases page](https://github.com/VitruvianSoftware/vitruvian-core/releases?q=vitruvian-courier), or install it with Homebrew. Homebrew 7 refuses to load anything from a third-party tap until you trust it, so trust ours once: `brew tap vitruviansoftware/tap && brew trust vitruviansoftware/tap && brew install --cask vitruviansoftware/tap/vitruvian-courier`. To update later, `brew upgrade --cask vitruviansoftware/tap/vitruvian-courier`.
3. Open the DMG and drag Vitruvian Courier onto Applications. Choose **Replace** when asked.
4. Open Vitruvian Courier. It opens without a warning, because the release is signed and notarised. Your chats are still there: the release uses the same data as the build you had.
5. If macOS asks whether Vitruvian Courier may use an item in your keychain, choose **Always Allow**. It asks once, because the release is signed in CI rather than on this Mac.
6. Check the version: Settings (⌘,) ▸ About shows "Version <version>".

## 2. Move Google Messages

Google Messages allows one web session at a time, so it can be linked to Beeper or to Vitruvian Courier, not both.

1. On your phone, open Google Messages, tap your profile picture, then **Device pairing**. Unpair the computer that is Beeper.
2. In Vitruvian Courier: Settings ▸ Accounts ▸ **Add Account** ▸ Google Messages. Read the note that linking here signs out other web sessions, then **Continue**.
3. Pair the way Vitruvian Courier offers: scan the QR code from **Device pairing ▸ QR code scanner** on your phone, or sign in with your Google account.
4. Wait for your conversations to appear in the inbox. The first sync can take a few minutes.

## 3. Check every network receives

For each network you use (WhatsApp, Signal, Telegram, Slack, Google Messages, Google Chat):

1. Have a message sent to you (or send one from your phone to yourself).
2. It should appear in Vitruvian Courier within a minute, with a notification.
3. Reply from Vitruvian Courier and check the reply arrives.

If one doesn't: Settings ▸ Accounts shows that account's status. **Reconnect…** signs in again without losing anything. Don't go on to step 5 until every network works.

## 4. Point Claude Code at Vitruvian Courier

Claude Code reaches Beeper through the `beeper` entry under `mcpServers` in `~/.claude.json` (port 23373). Vitruvian Courier speaks the same tools on port 23390, at `/v0/mcp`, so only the address and the token change. Keeping the name `beeper` means every tool keeps its name (`mcp__beeper__…`), so your permissions and habits keep working.

1. Keep a copy of the current settings, for going back: `cp ~/.claude.json ~/.claude.json.before-courier`
2. In Vitruvian Courier: Settings ▸ Integrations. Turn on **Allow connections**. The status says "Listening on 127.0.0.1:23390".
3. **New connection…**: name it "Claude Code", turn on "Can send messages" if Claude should be able to send, then **Create**. Copy the secret now: it is shown once.
4. In Terminal, replace the old entry with one that points at Vitruvian Courier (put the secret where it says `<secret>`):

   ```sh
   claude mcp remove beeper --scope user
   claude mcp add --scope user --transport http beeper http://127.0.0.1:23390/v0/mcp \
     --header "Authorization: Bearer <secret>"
   ```

5. Start a new Claude Code session and ask it to list your chat accounts. It should list all six networks. Then ask it to search your messages for a word you know is there.

## 5. Log out of Beeper

Only do this once steps 3 and 4 work.

1. In Beeper, open Settings and log out of your account.
2. Quit Beeper. In System Settings ▸ General ▸ Login Items, remove Beeper so it does not start again.
3. Optional: on your phone, look at the linked devices for each network (WhatsApp ▸ Linked devices, Signal ▸ Linked devices, Telegram ▸ Devices, Google Messages ▸ Device pairing). Remove any that belong to Beeper. If you can't tell which entry is which, leave it: Vitruvian Courier's is the one that was active just now.

## Going back

Vitruvian Courier keeps everything it has received, whatever you do here.

- **Before step 5**, Beeper is still signed in. To go back: in Beeper, link Google Messages again (this unlinks Vitruvian Courier's, because only one web session is allowed); put Claude Code back with `cp ~/.claude.json.before-courier ~/.claude.json`; quit Vitruvian Courier.
- **After step 5**, sign in to Beeper again first. Its networks may each ask you to link again, like a new computer. Then do the steps above.
- **If a Vitruvian Courier release itself is wrong**, install the build from your checkout instead: `bazel run --config=macos-app //apps/desktop/vitruvian-courier/app:install`. An older Vitruvian Courier refuses data that a newer one has upgraded, and says "update Vitruvian Courier". If that happens, stay on the newer one and report the fault.

The list to tick off as you go is [m6-acceptance.md](m6-acceptance.md).
