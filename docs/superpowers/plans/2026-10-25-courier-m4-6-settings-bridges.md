# Courier Milestone 4.6 Implementation Plan — Settings, Notifications, and the Bridges Pane

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Milestone 4.6 of Courier: the two-column Settings window (`⌘,`) with live settings search (`⌘F`), full notification options (sounds, sound effects + volume, delay/batching with OTP immediate bypass, repeat unread reminders, auto-copy OTP/2FA codes, System Settings / Notification Center controls, and per-account notification overrides carried from 4.4), the Accounts and Bridges panes (health, version, errors, **Restart Bridge**, **Remove Account…**, sub-account switches, Dock official-app removal, and Developer actions), **Report a Problem** as a local bundle (carrying 4.4's Ruling 10 stderr/crash scrubber), Login Item (`SMAppService.mainApp`), Touch ID app lock (`LAContext`), Dock and menu-bar menus, detached chat/space/thread windows (carried from 4.5a), and the hotkey editor + `⌘/` Keyboard Shortcuts sheet (carried from 4.3).

**Architecture:** The Go engine (`apps/desktop/courier/engine/internal/...`) gains a Ruling 10 crash/stderr export filter (`logscrub.ScrubStderrExport`), bounded rolling stderr capture (`engine-stderr.log`), SQLite migration 9 (`sub_accounts` and `"m.space"` parent portal tracking), thread-safe bridge restart (`Engine.RestartNetwork`), account removal (`Engine.RemoveAccount`), bridge module version inspection (`runtime/debug.ReadBuildInfo`), and JSON-RPC v7 methods (`bridges.list`, `bridges.restart`, `accounts.remove`, `accounts.subAccounts`, `accounts.setSubAccount`, `diagnostics.export`). The SwiftUI macOS 14.0 app (`apps/desktop/courier/app/Sources/CourierCore` and `Courier`) adds model-driven Settings search, extended `NotificationPreferences` + `NotificationCoordinator` timers, `SMAppService` and `LAContext` wrappers, `NSApplicationDelegate.applicationDockMenu(_:)` + `NSStatusBar` tray item, detached `NSWindow` controllers for chats/spaces/threads, a customizable hotkey registry, and light/dark PNG snapshot tests.

**Tech Stack:** Go 1.26, `maunium.net/go/mautrix@v0.31.0/bridgev2`, `go.mau.fi/mautrix-{whatsapp,signal,telegram,gmessages}@v0.2609.0`, `go.mau.fi/mautrix-slack@v0.2609.1`, SQLite (`go-sqlite3`), Swift 5.10 / SwiftUI / AppKit, `UserNotifications`, `ServiceManagement` (`SMAppService`), `LocalAuthentication` (`LAContext`), `AVFoundation` / `NSSound`, XCTest.

**Split decision:** None. All of spec §7 4.6 plus every item carried to 4.6 in `apps/desktop/courier/docs/m4-acceptance.md` fits cleanly in 14 cohesive tasks below. (Storage management, Command Bar `⌘J`, themes, wallpapers, custom CSS, zoom, font size, and compact mode remain in Milestone 4.7 per spec §7.)

---

## Summary for the Owner

### Today (what `main` already has)
- **Settings scene (`App.swift:72-85`):** A temporary two-tab `TabView` hosting `InboxSettingsPane.swift` (inbox sidebar/pinned/unread/previews/network-icon toggles, hover & double-click chat actions, default remind-later, auto-archive, mark-read-on-archive, after-archive/after-read actions, and bulk archive older chats) and `MessagesSettingsPane.swift` (timestamps, hide deleted,membership events, quick reactions, spellcheck, formatting bar, emoticon replacement, copy with timestamp, `↑` key behaviour, double-click message action, undo send window, click-pending-to-undo, default send-later, show typing, and Incognito mode).
- **Notifications (`NotificationPolicy.swift`, `NotificationCoordinator.swift`, `Notifier.swift`):** `NotificationPreferences` currently has two toggles (`requestNotificationsEnabled` and `typingNotificationsEnabled`). `NotificationCoordinator` already handles incoming messages, message requests, incoming calls, typing notifications, and action buttons (`Mark as Read`, `Remind in 1 Hour`, `Remind in 8 Hours`, inline reply).
- **Accounts & Engine (`engine.go`, `login.go`, `methods.go`, `SpaceBar.swift`):** `accounts.list` returns connected accounts and their `status.BridgeState`. `Engine` starts bridges once in `StartNetworks` (`e.hosts` is an unguarded `map[string]*host.Host`) and has `Stop()`, but has no `RestartNetwork` or `RemoveAccount`. `CommandSet` registers `accounts` (`command Accounts`) and opens `AddNetworkView` as a temporary stand-in until 4.6.
- **Log scrubbing (`logscrub.go`, `courier-engine/main.go`, `courier-engine-cli/main.go`, `EngineSupervisor.swift`):** `logscrub.Writer` scrubs structured JSON lines written through `zerolog` on `stderr`, and `EngineSupervisor` retains the last 500 `stderr` lines in memory (`recentErrorOutput`). However, `courier-engine/main.go:93` prints raw startup errors (`fmt.Fprintln(stderr, "courier-engine:", err)`) containing the full data directory path (`/Users/<name>/...`), `courier-engine-cli/main.go:138` prints raw errors (`fmt.Fprintln(os.Stderr, "error:", err)`), and an unrecovered panic in a background goroutine writes directly to file descriptor 2 (`os.Stderr`), bypassing `logscrub.Writer`.
- **Dock, Menu Bar & Quit (`AppDelegate.swift`, `MenuBar.swift`, `SpacesModel.swift`):** `AppDelegate` mirrors `SpacesModel.badgeCount` (`inbox` `attention_chats`) onto `NSApp.dockTile.badgeLabel`, keeps the app running when the main window closes (`applicationShouldTerminateAfterLastWindowClosed` returns `false`), and confirms quit while Undo Send messages are held. There is no Dock menu (`applicationDockMenu`), no menu-bar status item, no Login Item toggle, and no Touch ID lock.
- **Parallel 4.5b dependencies:** Milestone 4.5b (`docs/superpowers/plans/2026-10-25-courier-m4-5b-media.md`) is being built in parallel. We note every touchpoint explicitly (`needs 4.5b Task N`):
  - **Task 2 & Task 4** note that 4.5b Task 2 bumps `protocol.json` to 7 and adds SQLite migration 9 (`testdata/m9.sql`); whichever branch lands second bumps the number by 1 (migration 10 / protocol 8).
  - **Task 5** extends `NotificationCoordinator.swift` and `Notifier.swift` alongside 4.5b Task 4 (which adds media thumbnail attachments).
  - **Task 12** includes the General/Appearance media controls added by 4.5b Tasks 7–10 (`automaticallyPlayNextVoiceNote`, `selectedMicrophoneUID`, `downloadsLocationPath`, `alwaysAskBeforeDownloading`, `loadExternalEmbeds`, `disableOutgoingLinkPreviews`) when 4.5b is present.

### What 4.6 adds
1. **Ruling 10 Crash & Stderr Export Sanitizer (Task 1):**
   - `logscrub.ScrubStderrExport` keeps **only** scrubbed JSON log lines and Go stack-frame code-location lines (`goroutine N [state]:`, `<pkg>.<fn>(...)` with call arguments stripped to `(...)`, and `\t<file>:<line> +0x...` with local checkout/GOPATH prefixes stripped to module-relative paths).
   - Replaces everything after `panic:` and `fatal error:` with a fixed token (`panic: [redacted]`, `fatal error: [redacted]`).
   - Scrubs `/Users/<name>` home-directory paths and runs `logscrub.Redact` on `courier-engine:` startup errors in `courier-engine/main.go` and `error:` lines in `courier-engine-cli/main.go`.
   - Redirects/tees fd 2 (`os.Stderr`) in `courier-engine` through a pipe into both the parent stderr pipe and a bounded 256 KB rolling `engine-stderr.log` (`0600`) in the data directory so background-goroutine crashes are captured and scrubbed on export.
2. **Sub-Accounts & `"m.space"` Parent Portals (Task 2):**
   - Migration 9 (or 10 after 4.5b) adds `sub_accounts` and `rooms.is_space` / `rooms.parent_space_id`.
   - `host.go` stops inserting `bridgev2` `"m.space"` parent portals (Slack teams, WhatsApp Communities, Telegram Forums) as empty chat rows in the inbox, and instead records them—plus bot DM chats (`profiles.is_bot = 1`)—as per-account **Sub-Accounts** with on/off and `Show in Inbox` (`all` / `dms` / `none`) controls and **Refresh List**.
3. **Restart Bridge & Remove Account (Tasks 3–4):**
   - `Engine.RestartNetwork(ctx, name)` safely cancels any active login session on `name`, stops the `bridgev2.Bridge` (`StopWithTimeout(5*time.Second)`), closes `<name>.db`, constructs a fresh `host.Host`, and restarts connectors and logins without restarting Courier.
   - `Engine.RemoveAccount(ctx, network, accountID, logoutRemote, deleteChats)` runs `UserLogin.Delete` (`LogoutRemote` optional, `BlockingCleanup: true`), cleans up `login_state`, `sub_accounts`, and (when requested or last login on the network) the account's rooms, events, and FTS rows in `courier.db`.
   - `bridges.list` reports each bridge's state, Go module path and version (`runtime/debug.ReadBuildInfo`), start timestamp, error reason, and accounts.
4. **Full Notification Options & Per-Account Overrides (Task 5):**
   - Sound effects (`Never`, `Only for sent messages`, `Only for received messages`, `Always`) + volume slider; message and group notification toggles + sound picker; `Notify when app is in focus`; `Notify when someone reacts to a message`; `Delay notifications for` (`0s`, `10s`, `30s`, `1m`, `2m`, `5m` with **immediate bypass for OTP/2FA codes**); `Repeat notification if still unread after` (`Never`, `2m`, `5m`, `10m`); `Auto copy OTP/2FA codes` (`NSPasteboard.ConcealedType` + notify even when muted); per-account notification overrides (`Enable notifications`, `Show message previews`, `Notification sound`); and buttons to open macOS System Settings Notifications or restart Notification Center (`killall NotificationCenter`).
5. **Login Item, Touch ID Lock, Dock Menu, Tray Icon & Native Menu Bar (Tasks 6–7):**
   - `SMAppService.mainApp` for `Open Beeper at login`, plus `Keep Beeper minimized on launch` and `Quit Beeper when closing the main window`.
   - `LAContext` Touch ID / passcode app lock (`Require Touch ID authentication on launch`, `command Lock app`, `menu:Beeper Lock App`) with `AppLockOverlay`, notification preview redaction while locked, and empty Dock menu while locked.
   - Dynamic Dock menu (`Unread Chats` up to 5, `Recent Chats` up to 5), `Dock badge count` (`None`, `All unread chats`, `Unmuted unread chats`), menu-bar tray icon (`Show menu bar icon`, `Minimize to Menu Bar` `⌘⌥Q`), and full macOS menu bar (`Beeper`, `File`, `View`, `Help`).
6. **Detached Windows, Hotkey Editor, Accounts/Bridges Panes, Report a Problem & Two-Column Settings Shell (Tasks 8–12):**
   - Detached windows for a chat (`menu:File Open Chat in New Window`, double-click chat), a space (`command Open space in new window`), and a thread (`ThreadedRepliesBrowserWindow.tsx`).
   - Full Hotkey Registry & Recorder (`HotkeysPrefsSubView.tsx`, conflict check, modifier validation, Texts.app preset, `⌘/` Keyboard Shortcuts sheet).
   - Accounts pane, single Account detail pane (`command Account`, Dock official-app removal, Sub-Accounts, per-account notifications, Remove Account), and Bridges pane (`command Bridges`).
   - Report a Problem local `.zip` bundle (`⌘⇧P`, `diagnostics.export` + Ruling 10 stderr scrubber, optional message/room details, `NSSavePanel`) + `Copy Message Details` on the message menu.
   - Two-column Settings window (`⌘,`) with `SearchSuggestions` (`⌘F`), Time Suggestions editor (carried from 4.1), Primary/Secondary composer buttons (carried from 4.3), Quick Replies editor, and About pane.

### Surprises found in the code and bridges
1. **`bridgev2.Bridge.StopWithTimeout` is one-way (`maunium.net/go/mautrix@v0.31.0/bridgev2/bridge.go:455-495`):**
   - Calling `br.StopWithTimeout(timeout)` sets `br.stopping.Store(true)` (`bridge.go:461`), cancels `br.cancelBackgroundCtx()`, and closes `br.DB` (`bridge.go:488`). A stopped `bridgev2.Bridge` cannot be started again in place. To implement **Restart Bridge** (`bridges.restart`), `Engine.RestartNetwork` must close the existing `*host.Host` and call `host.Start` with a fresh connector from `networks.Spec.Factory()`.
2. **`Engine.hosts` and `login.Manager.hosts` have no mutex on `main` (`engine.go:34`, `login.go:42`):**
   - On `main`, `e.hosts` is populated once in `StartNetworks` before RPC clients connect, and `login.Manager` holds the raw `map[string]*host.Host` reference. Replacing `e.hosts[name]` during `bridges.restart` would race with concurrent RPC calls (`Host(name)`, `HostForRoom`, `Status`) and `login.Manager`. Task 3 adds `hostsMu sync.RWMutex` to `Engine` and passes a locked `Host(name)` lookup + `CancelNetwork(name)` hook to `login.Manager`.
3. **Slack's `LogoutRemote` revokes the browser's `xoxc-` session token (`go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/client.go:640-655`):**
   - When `UserLogin.Delete` is called with `LogoutRemote: true` (`maunium.net/go/mautrix@v0.31.0/bridgev2/userlogin.go:289-303`), `SlackClient.LogoutRemote` calls `cli.SendAuthSignoutContext(ctx)` (`client.go:644`). Because Courier links Slack by reading the user's browser cookie (`CookieCollector`), `SendAuthSignoutContext` invalidates the user's active browser Slack session! By contrast, WhatsApp (`cli.Logout`), Signal (`s.Client.Unlink`), Telegram (`AuthLogOut`), and Google Messages (`cli.Unpair`) unlink only the companion device. Task 3 and Task 10 therefore give the Remove Account confirmation dialog an explicit checkbox: **"Also sign out on <Network>"** (default **on** for companion-device networks WhatsApp, Signal, Telegram, Google Messages; default **off** for Slack with a note that signing out on Slack also signs out the browser session the token came from).
4. **`bridgev2` creates `"m.space"` rooms for Slack teams, WhatsApp Communities, and Telegram Forums (`bridgev2/portal.go:5378-5379`):**
   - `SlackClient.getTeamInfo` (`mautrix-slack@v0.2609.1/pkg/connector/chatinfo.go:322,380`), `WhatsAppClient.wrapChatInfo` (`mautrix-whatsapp@v0.2609.0/pkg/connector/chatinfo.go:346,349`), and `TelegramClient` (`mautrix-telegram@v0.2609.0/pkg/connector/chatinfo.go:179,186,212`) set `Type = database.RoomTypeSpace` (`"space"`), which causes `bridgev2/portal.go:5379` to call `Bot.CreateRoom` with `req.CreationContent["type"] = "m.space"`. On `main`, `host.go:200` ignores `CreationContent["type"]` and inserts `"m.space"` portals into `rooms` as regular group chats. Task 2 marks `"m.space"` rooms with `is_space = 1` so they never clutter the chat list and instead populate `sub_accounts`.
5. **Go runtime panics write directly to fd 2, bypassing `logscrub.Writer` (`courier-engine/main.go:204`):**
   - Wrapping `stderr` in `zerolog.New(logscrub.New(stderr))` only scrubs structured JSON logs emitted through `zerolog`. If a bridge goroutine panics, the Go runtime writes `panic: <value>` and goroutine stack frames directly to file descriptor 2 (`os.Stderr`). Task 1 both captures stderr into a rolling file and passes all exported stderr lines through `logscrub.ScrubStderrExport` (Ruling 10) before any diagnostic bundle is created.

### Decisions for you before or during implementation
1. **Slack "Remove Account" remote sign-out default:** As noted in Surprise 3, `SlackClient.LogoutRemote` calls `auth.signout`, which signs out the user's browser Slack session if they linked via browser cookies. The plan defaults **"Also sign out on Slack"** to **off** (and **on** for WhatsApp, Signal, Telegram, and Google Messages, where `LogoutRemote` only unlinks Courier's companion device). Tell us if you prefer it on by default for Slack too.
2. **Sub-Accounts scope:** The plan populates an account's **Sub-Accounts** list from (a) `bridgev2` `"m.space"` parent portals (Slack workspaces/teams, WhatsApp Communities, Telegram Forums) and (b) bot DM chats (`profiles.is_bot = 1`, e.g., Slack apps/bots and Telegram bots), with per-sub-account on/off and `Show in Inbox` (`All Messages` / `Only DMs` / `None`) plus **Refresh List**.

### Main risks
- **Bridge SQLite lock contention during `bridges.restart`:** If `host.Start` runs before the old `bridgev2.Bridge` has finished closing its SQLite connection (`<network>.db`), SQLite or `datadir` can report a busy database. Task 3 serializes `RestartNetwork` per network under `restartMu`, waits for `h.Close()` (which runs `Bridge.StopWithTimeout(5*time.Second)` then `DB.Close()`), and only then opens the new `host.Host`.
- **PII leakage in crash stacks or startup errors (Ruling 10):** A panic value (`panic: ...`) or function argument in a stack trace could hold a phone number, token, or message pointer, and `courier-engine:` startup errors hold `/Users/<username>/...`. Task 1 enforces an allowlist parser (`logscrub.ScrubStderrExport`) that drops any non-JSON line that is not a recognized Go stack-frame header/location, replaces everything after `panic:` / `fatal error:` with `[redacted]`, strips function arguments to `(...)`, and replaces `/Users/<username>` with `~`.

---

## Per-Network Logout, Restart, and Sub-Account Matrix

Every bridge fact below is verified from `~/go/pkg/mod` at the pinned module versions (`maunium.net/go/mautrix@v0.31.0`, `go.mau.fi/mautrix-{whatsapp,signal,telegram,gmessages}@v0.2609.0`, `go.mau.fi/mautrix-slack@v0.2609.1`). Exact `grep -rn` commands are in the Appendix.

| Network | `LoadUserLogin` (Restart) | `Disconnect` (Stop / Local Remove) | `LogoutRemote` (Remote Unlink) | Sub-Account / `"m.space"` & Bot Source | Official macOS App Bundle ID (Dock Removal) |
|---|---|---|---|---|---|
| **BridgeV2 Core** (`maunium.net/go/mautrix@v0.31.0`) | `Bridge.StartLogins` (`bridgev2/bridge.go:366`) → `unlockedLoadUserLoginsByMXID` (`bridgev2/userlogin.go:106`) | `Bridge.StopWithTimeout` (`bridgev2/bridge.go:455`) → `UserLogin.DisconnectWithTimeout` (`bridgev2/bridge.go:469`) | `UserLogin.Delete` (`bridgev2/userlogin.go:289-339`) calls `ul.Client.LogoutRemote(ctx)` (`userlogin.go:300`), deletes `user_login` row (`database/userlogin.go:88`), and cleans up portals | `database.RoomTypeSpace` (`bridgev2/database/portal.go:29`, `bridgev2/portal.go:5378-5379`, `bridgev2/space.go:108-132`); `Ghost.IsBot` (`bridgev2/database/ghost.go:88`) | — |
| **WhatsApp** (`go.mau.fi/mautrix-whatsapp@v0.2609.0`) | `WhatsAppConnector.LoadUserLogin` (`pkg/connector/client.go:46`) | `WhatsAppClient.Disconnect` (`pkg/connector/client.go:381-386`) + `WhatsAppConnector.Stop` (`pkg/connector/connector.go:176-180`) | `WhatsAppClient.LogoutRemote` (`pkg/connector/client.go:388-401`): calls `cli.Logout(ctx)`, `wa.Disconnect()`, and `Main.DB.Conversation.DeleteAll(ctx, wa.UserLogin.ID)` | Community parent portals set `Type = database.RoomTypeSpace` and `ParentID` (`pkg/connector/chatinfo.go:346-350, 378-382`); bot ghosts set `IsBot: ptr.Ptr(jid.IsBot())` (`pkg/connector/userinfo.go:265, 484`) | `net.whatsapp.WhatsApp` |
| **Signal** (`go.mau.fi/mautrix-signal@v0.2609.0`) | `SignalConnector.LoadUserLogin` (`pkg/connector/connector.go:107`) | `SignalClient.Disconnect` (`pkg/connector/client.go:287-296`): calls `stopChatSync()` and `Client.StopReceiveLoops()` | `SignalClient.LogoutRemote` (`pkg/connector/client.go:89-105`): calls `Client.Unlink(ctx)`, `Client.StopReceiveLoops()`, and `Main.Store.DeleteDevice(..., &Client.Store.DeviceData)` | Sets `IsBot: &isBot` (`false`) (`pkg/connector/chatinfo.go:105`); no `"m.space"` portals | `org.whispersystems.signal-desktop` |
| **Telegram** (`go.mau.fi/mautrix-telegram@v0.2609.0`) | `TelegramConnector.LoadUserLogin` (`pkg/connector/connector.go:51`) | `TelegramClient.Disconnect` (`pkg/connector/client.go:563-577`): cancels `clientCancel` and waits on `clientDone` | `TelegramClient.LogoutRemote` (`pkg/connector/client.go:585-625`): calls `client.API().AuthLogOut(ctx)` (5s timeout), `Disconnect()`, `ScopedStore.DeleteUserState`, `DeleteChannelStateForUser`, `DeleteAccessHashesForUser` | Forum/Community parent portals set `Type = database.RoomTypeSpace` and `ParentID` (`pkg/connector/chatinfo.go:179-193, 212`); bot users set `IsBot: &user.Bot` (`pkg/connector/userinfo.go:280`) | `ru.keepcoder.Telegram` / `org.telegram.desktop` |
| **Slack** (`go.mau.fi/mautrix-slack@v0.2609.1`) | `SlackConnector.LoadUserLogin` (`pkg/connector/client.go:64`) | `SlackClient.Disconnect` (`pkg/connector/client.go:618-634`): disconnects `RTM` and cancels `stopConnection` | `SlackClient.LogoutRemote` (`pkg/connector/client.go:640-655`): calls `disconnect()`, if `IsRealUser` calls `cli.SendAuthSignoutContext(ctx)` (`client.go:644`), and clears `Token`, `CookieToken`, `AppToken` | Team/workspace portal sets `Type: ptr.Ptr(database.RoomTypeSpace)` (`pkg/connector/chatinfo.go:380`) and channels set `ParentID: ptr.Ptr(slackid.MakeTeamPortalID(s.TeamID))` (`chatinfo.go:322`); bots set `isBot = isBot \|\| info.IsBot \|\| info.IsAppUser` (`chatinfo.go:458, 468`) | `com.tinyspeck.slackmacgap` |
| **Google Messages** (`go.mau.fi/mautrix-gmessages@v0.2609.0`) | `GMConnector.LoadUserLogin` (`pkg/connector/client.go:100`) | `GMClient.Disconnect` (`pkg/connector/client.go:195-205`): calls `cli.Disconnect()` | `GMClient.LogoutRemote` (`pkg/connector/client.go:236-245`): calls `cli.Unpair(ctx)`, `Disconnect()`, sets `Meta.Session = nil` and `Client = nil` | Sets `IsBot: ptr.Ptr(false)` (`pkg/connector/chatinfo.go:337`); no `"m.space"` portals | — (no official macOS desktop app; Dock button hidden) |

---

## Global Constraints

1. **Privacy & Outbound Connections (Hard Rule 5):**
   - Nothing leaves the Mac unless the person asks for it.
   - **Outbound connections added by this plan:**
     1. **`accounts.remove` with `logout_remote: true` (triggered only when the user clicks "Remove Account…" and confirms with "Also sign out on <Network>" checked):** sends a single remote logout/unlink request over the account's existing authenticated bridge connection to that network's server:
        - WhatsApp: `whatsmeow.Client.Logout` (`mautrix-whatsapp@v0.2609.0/pkg/connector/client.go:390`)
        - Signal: `signalmeow.Client.Unlink` (`mautrix-signal@v0.2609.0/pkg/connector/client.go:94`)
        - Telegram: `tg.Client.AuthLogOut` (`mautrix-telegram@v0.2609.0/pkg/connector/client.go:601`)
        - Slack: `slack.Client.SendAuthSignoutContext` (`mautrix-slack@v0.2609.1/pkg/connector/client.go:644`, only if the user explicitly checks "Also sign out on Slack")
        - Google Messages: `libgm.Client.Unpair` (`mautrix-gmessages@v0.2609.0/pkg/connector/client.go:238`)
     2. **`bridges.restart` (triggered only when the user clicks "Restart Bridge" in the Bridges pane or Developer menu and confirms):** disconnects and reconnects the bridge's existing linked `UserLogin` sessions to their respective chat network servers (`WhatsApp`, `Signal`, `Telegram`, `Slack`, `Google Messages`). No new third-party endpoints are contacted.
     3. **Help menu external links (triggered only when the user clicks `Open Beeper Help`, `Open Beeper.com`, or `Follow @Beeper on X` in the Help menu):** opens the URL in the user's default browser via `NSWorkspace.shared.open(_:)`.
   - **Zero telemetry or crash uploads:** `Report a Problem` (`⌘⇧P`) writes a local `.zip` bundle to the path chosen by the user in `NSSavePanel`. No Sentry, rageshake server, or analytics endpoint is ever contacted.
2. **macOS 14.0 Deployment Target APIs (Hard Rule 4):**
   - `apps/desktop/courier/app/BUILD` sets `minimum_os_version = "14.0"` (`Package.swift` `.macOS(.v14)`). Every framework and symbol used in this plan exists in macOS 14.0:
     - `ServiceManagement`: `SMAppService.mainApp`, `SMAppService.Status`, `register()`, `unregister()` (macOS 13.0+).
     - `LocalAuthentication`: `LAContext`, `LAPolicy.deviceOwnerAuthenticationWithBiometrics`, `LAPolicy.deviceOwnerAuthentication`, `canEvaluatePolicy(_:error:)`, `evaluatePolicy(_:localizedReason:)` (macOS 10.12.2+).
     - `UserNotifications`: `UNUserNotificationCenter`, `UNMutableNotificationContent`, `UNNotificationSound`, `UNNotificationSoundName` (macOS 10.14+).
     - `AppKit`: `NSApplicationDelegate.applicationDockMenu(_:)`, `NSApp.dockTile.badgeLabel`, `NSApp.setActivationPolicy(_:)`, `NSStatusBar.system.statusItem(withLength:)`, `NSStatusItem`, `NSMenu`, `NSMenuItem`, `NSSavePanel`, `NSOpenPanel`, `NSSound`, `NSPasteboard`, `NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")`, `NSWorkspace.shared.open(_:)`, `NSWindow`.
3. **View Verification via Light & Dark PNG Snapshots (Hard Rule 6):**
   - Every new or updated SwiftUI view is rendered in both `.light` and `.dark` appearances via `assertLightAndDarkSnapshot` in `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`. There is no fake-network app mode.
4. **Bazel-Only Repo Operations:**
   - Run Go and Swift tests via `bazel test //apps/desktop/courier/...`. Never run raw `go test` or `swift test`.

---

## Review Focus

1. **Ruling 10 completeness (`logscrub.ScrubStderrExport`):** Does the stderr/crash export drop every non-JSON line except Go stack-frame headers (`goroutine N [...]:`), function lines (`<pkg>.<fn>(...)` with arguments stripped to `(...)`), and file/line locations (`\t<relpath>:<line> +0x...` with `/Users/<name>` and build roots stripped), and replace everything after `panic:` and `fatal error:` with `[redacted]`? Are `courier-engine:` and `courier-engine-cli` startup error lines scrubbed for `/Users/<name>` and `logscrub.Redact`?
2. **Thread-safe `RestartNetwork` and `RemoveAccount`:** Are `Engine.hosts` accesses guarded by `hostsMu`? Does `RestartNetwork` cancel any in-flight interactive login on that network and wait for `Host.Close()` before re-opening `<network>.db`?
3. **Every setting changes the behaviour it names:** Does `Delay notifications for` hold normal message notifications for the configured delay while letting OTP/2FA messages through immediately? Does `Repeat notification if still unread after` fire only if the chat is still unread when the timer expires? Do per-account notification overrides (`enabled`, `showPreviews`, `sound`) take precedence over global defaults?
4. **Touch ID lock privacy:** When the app is locked (`SystemLifecycleModel.isLocked == true`), are all windows covered by `AppLockOverlay`, notification body previews hidden (`"New message"`), and `applicationDockMenu(_:)` returning `nil` / empty?

---

## Task 1: Engine Crash & Stderr Export Sanitizer (Ruling 10)

**Files:**
- Modify: `apps/desktop/courier/engine/internal/logscrub/logscrub.go`
- Create: `apps/desktop/courier/engine/internal/logscrub/stack.go`
- Create: `apps/desktop/courier/engine/internal/logscrub/stack_test.go`
- Modify: `apps/desktop/courier/engine/internal/logscrub/logscrub_test.go`
- Modify: `apps/desktop/courier/engine/cmd/courier-engine/main.go`
- Modify: `apps/desktop/courier/engine/cmd/courier-engine/main_test.go`
- Modify: `apps/desktop/courier/engine/cmd/courier-engine-cli/main.go`
- Modify: `apps/desktop/courier/engine/cmd/courier-engine-cli/main_test.go`

**Interfaces:**
```go
// In package logscrub (stack.go):

// ScrubPath replaces any macOS/Unix home directory prefix (/Users/<name>/ or /home/<name>/)
// and os.UserHomeDir() with "~/", and redacts tokens/phones/emails via Redact.
func ScrubPath(s string) string

// ScrubStartupError formats a startup error line for courier-engine or courier-engine-cli
// with home-directory paths replaced by "~" and all secrets/PII scrubbed via Redact.
func ScrubStartupError(prefix string, err error) string

// ScrubExportLine filters a single stderr line for Report a Problem (Ruling 10):
//  1. A JSON log line (starts with '{') is passed through Line([]byte(s)); if it is valid
//     scrubbed JSON and not the {"msg":"unreadable log line dropped"} fallback, it is kept.
//  2. "panic: <anything>" -> ("panic: [redacted]", true)
//  3. "fatal error: <anything>" -> ("fatal error: [redacted]", true)
//  4. "courier-engine: <anything>" -> ("courier-engine: " + ScrubPath(Redact(rest)), true)
//  5. Go stack-frame lines:
//     - "goroutine <N> [<state>]:" -> kept as-is
//     - "created by <pkg>.<fn> in goroutine <N>" -> kept as-is
//     - "<pkg>.<fn>(<args>)" -> arguments inside trailing (...) replaced with "(...)"
//     - "\t<filepath>:<line> +0x<hex>" or "\t<filepath>:<line>" -> build/home path prefix
//       stripped to module-relative path (e.g. "\tgithub.com/VitruvianSoftware/courier/.../file.go:42 +0x1a")
//  6. Every other line is dropped ("", false).
func ScrubExportLine(line string) (scrubbed string, keep bool)

// ScrubStderrExport reads raw stderr text and returns only the kept lines from ScrubExportLine.
func ScrubStderrExport(raw string) []string
```

**Steps:**
- [ ] Implement `ScrubPath`, `ScrubStartupError`, `ScrubExportLine`, and `ScrubStderrExport` in `apps/desktop/courier/engine/internal/logscrub/stack.go`.
- [ ] In `apps/desktop/courier/engine/cmd/courier-engine/main.go`:
  - Replace `fmt.Fprintln(stderr, "courier-engine:", err)` (`main.go:93`) with `fmt.Fprintln(stderr, logscrub.ScrubStartupError("courier-engine:", err))` so a data-path error (`/Users/<name>/Library/Application Support/Courier/...`) never prints the Mac's account name in plain text.
  - Add a bounded rolling file writer (`engine-stderr.log`, mode `0600`, max 256 KB, keeping the newest half on rollover) inside `cfg.data` once `sqlite.PrivateDir(cfg.data)` succeeds, and tee `stderr` through `logscrub.New` so structured logs and crash output are available to `diagnostics.export`.
- [ ] In `apps/desktop/courier/engine/cmd/courier-engine-cli/main.go`:
  - Replace `fmt.Fprintln(os.Stderr, "error:", err)` (`main.go:138`) with `fmt.Fprintln(os.Stderr, logscrub.ScrubStartupError("error:", err))`.

**Tests:**
- [ ] In `stack_test.go`, test `ScrubStderrExport` against:
  - A multi-goroutine Go panic dump containing a phone number (`+14155550199`), a Slack token (`xoxc-123-456`), a message body inside `panic: failed to parse "+14155550199: secret message"`, pointer hex arguments on stack frames (`0x1400012a000`), and `/Users/alice/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/bridgev2/portal.go:2690 +0x1c4`. Verify `panic: [redacted]`, `fatal error: [redacted]`, arguments replaced with `(...)`, `/Users/alice/...` stripped to `maunium.net/go/mautrix@v0.31.0/bridgev2/portal.go:2690 +0x1c4`, and arbitrary non-JSON / non-stack lines dropped.
- [ ] In `courier-engine/main_test.go` and `courier-engine-cli/main_test.go`, verify that a startup failure under `/Users/alice/...` outputs `~/...` with no raw Mac username or secret.
- [ ] Run `bazel test //apps/desktop/courier/engine/internal/logscrub/... //apps/desktop/courier/engine/cmd/...`.

---

## Task 2: SQLite Migration 9 (`sub_accounts` & `"m.space"` Filtering) and Account Removal Store Queries

> **Parallel 4.5b note:** 4.5b Task 2 also adds a migration 9 (`media_played`). If 4.5b lands on `main` first, renumber this migration to 10 (`SchemaVersion = 10`, `testdata/m10.sql`).

**Files:**
- Modify: `apps/desktop/courier/engine/internal/store/migrate.go`
- Modify: `apps/desktop/courier/engine/internal/store/migrate_test.go`
- Create: `apps/desktop/courier/engine/internal/store/accounts.go`
- Create: `apps/desktop/courier/engine/internal/store/accounts_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/inbox.go`
- Modify: `apps/desktop/courier/engine/internal/store/spaces.go`
- Modify: `apps/desktop/courier/engine/internal/store/BUILD`
- Modify: `apps/desktop/courier/engine/internal/host/host.go`
- Modify: `apps/desktop/courier/engine/internal/host/host_test.go`

**Interfaces:**
```go
// In package store (accounts.go):

type SubAccount struct {
    Network     string // e.g. "slack", "telegram", "whatsapp"
    LoginID     string // bridgev2 user_login.id
    SubID       string // room_id of the m.space portal or bot DM room
    Title       string
    AvatarURI   string
    Kind        string // "space" (Slack workspace, WA community, TG forum) | "bot" (bot DM)
    Enabled     bool
    ShowInInbox string // "all" | "dms" | "none"
}

func (s *Store) SetRoomSpace(ctx context.Context, roomID string, isSpace bool, parentSpaceID string) error
func (s *Store) UpsertSubAccount(ctx context.Context, sub SubAccount) error
func (s *Store) SubAccounts(ctx context.Context, network, loginID string) ([]SubAccount, error)
func (s *Store) UpdateSubAccount(ctx context.Context, network, loginID, subID string, enabled *bool, showInInbox *string) error
func (s *Store) SyncBotSubAccounts(ctx context.Context, network, loginID string) ([]SubAccount, error)

// RemoveAccountData removes login_state and sub_accounts for (network, loginID).
// When deleteChats is true, it also deletes all rooms (and cascading events/members/state/reads/FTS)
// belonging to (network, loginID), and if no logins remain on network, deletes rooms with login_id=''
// on that network plus account_prefs and space_layout entries for account:<network>.
func (s *Store) RemoveAccountData(ctx context.Context, network, loginID string, deleteChats bool) error
```

**Steps:**
- [ ] In `migrate.go`, add migration 9 (bump `SchemaVersion = 9`):
  ```sql
  ALTER TABLE rooms ADD COLUMN is_space INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE rooms ADD COLUMN parent_space_id TEXT NOT NULL DEFAULT '';
  CREATE TABLE sub_accounts (
    network TEXT NOT NULL,
    login_id TEXT NOT NULL,
    sub_id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    avatar_uri TEXT NOT NULL DEFAULT '',
    kind TEXT NOT NULL DEFAULT 'space',
    enabled INTEGER NOT NULL DEFAULT 1,
    show_in_inbox TEXT NOT NULL DEFAULT 'all' CHECK (show_in_inbox IN ('all', 'dms', 'none')),
    PRIMARY KEY (network, login_id, sub_id)
  );
  ```
- [ ] In `inbox.go` and `spaces.go`:
  - Exclude `r.is_space = 1` from `InboxPage` and `spaceCountsSQL` so `"m.space"` parent portals never appear as empty chat rows.
  - Extend `shownInInboxSQL` and `InboxPage` so a room whose `parent_space_id` or `room_id` matches a `sub_accounts` row respects `sub_accounts.enabled = 1` (when `enabled = 0`, the sub-account's rooms are hidden from both the inbox and the account space) and `sub_accounts.show_in_inbox` (`all`, `dms`, `none`).
- [ ] In `host.go`:
  - In `bot.CreateRoom` (`host.go:200`), inspect `req.CreationContent["type"]`: when it equals `"m.space"`, call `h.Store.SetRoomSpace(ctx, roomID, true, "")` and `h.Store.UpsertSubAccount` (using the `m.bridge` initial state's `Receiver` as `LoginID`).
  - In `bot.checkRoomState`, handle `"m.space.parent"` (setting `parent_space_id = stateKey` on the child room) and `"m.space.child"` (setting `parent_space_id = roomID` on the child `stateKey` room when `content.via` is non-empty, or `""` when `via` is empty).
- [ ] Implement `SubAccounts`, `UpdateSubAccount`, `SyncBotSubAccounts` (which discovers DM rooms on `(network, loginID)` whose other member has `profiles.is_bot = 1`), and `RemoveAccountData` in `accounts.go`.

**Tests:**
- [ ] In `migrate_test.go` and `accounts_test.go`, test migration upgrade from v8 to v9, `"m.space"` exclusion from `InboxPage` and `Spaces`, sub-account `enabled` / `show_in_inbox` filtering on child rooms and bot DMs, and `RemoveAccountData` both with one account and with multiple accounts on the same network.
- [ ] In `host_test.go`, test that `CreateRoom` with `CreationContent: {"type": "m.space"}` marks the room as `is_space = 1` and creates a `sub_accounts` entry, and `SendState` with `m.space.parent` links child rooms to that sub-account.
- [ ] Run `bazel test //apps/desktop/courier/engine/internal/store/... //apps/desktop/courier/engine/internal/host/...`.

---

## Task 3: Engine Bridge Lifecycle (`RestartNetwork`, `RemoveAccount`, `RefreshSubAccounts`, Bridge Build Info)

**Files:**
- Modify: `apps/desktop/courier/engine/internal/engine/engine.go`
- Modify: `apps/desktop/courier/engine/internal/engine/engine_test.go`
- Modify: `apps/desktop/courier/engine/internal/login/login.go`
- Modify: `apps/desktop/courier/engine/internal/login/login_test.go`
- Modify: `apps/desktop/courier/engine/internal/networks/networks.go`
- Modify: `apps/desktop/courier/engine/internal/networks/networks_test.go`

**Interfaces:**
```go
// In package networks (networks.go):
type Spec struct {
    Name        string
    DisplayName string
    ModulePath  string // e.g. "go.mau.fi/mautrix-whatsapp"
    Factory     func() bridgev2.NetworkConnector
}

// ModuleVersions returns map[modulePath]version from runtime/debug.ReadBuildInfo(),
// plus "maunium.net/go/mautrix" version.
func ModuleVersions() map[string]string

// In package engine (engine.go):
type BridgeReport struct {
    Network      string
    DisplayName  string
    BridgeID     string
    ModulePath   string
    Version      string
    MautrixVer   string
    State        string // status.BridgeStateEvent
    Error        string
    Message      string
    StartedAtMS  int64
}

func (e *Engine) Bridges(ctx context.Context) ([]BridgeReport, error)
func (e *Engine) RestartNetwork(ctx context.Context, name string) error
func (e *Engine) RemoveAccount(ctx context.Context, network, accountID string, logoutRemote, deleteChats bool) error
func (e *Engine) RefreshSubAccounts(ctx context.Context, network, accountID string) ([]store.SubAccount, error)
```

**Steps:**
- [ ] In `networks.go`, populate `ModulePath` on each `Spec` (`go.mau.fi/mautrix-whatsapp`, `go.mau.fi/mautrix-signal`, `go.mau.fi/mautrix-telegram`, `go.mau.fi/mautrix-slack`, `go.mau.fi/mautrix-gmessages`) and implement `ModuleVersions()` using `runtime/debug.ReadBuildInfo()`.
- [ ] In `login.go`, add `CancelNetwork(network string)` to `login.Manager` (cancels any active interactive login session for `network`) and add `SetHost(network string, h *host.Host)` guarded by `m.mu` so `RestartNetwork` updates `login.Manager`'s host reference without a map race.
- [ ] In `engine.go`:
  - Add `hostsMu sync.RWMutex`, `restartMu sync.Mutex`, and `startedAt map[string]time.Time` to `Engine`.
  - Guard `Host(name)`, `HostForRoom`, `Status(name)`, and `Stop()` with `hostsMu`.
  - Implement `RestartNetwork(ctx, name)`:
    1. Acquire `restartMu` and validate `name` is a registered `networks.Spec`.
    2. If `e.login != nil`, call `e.login.CancelNetwork(name)`.
    3. Remove old `*host.Host` under `hostsMu` and call `old.Close()` (which runs `Bridge.StopWithTimeout(5*time.Second)` at `bridgev2/bridge.go:455` and closes `<name>.db`).
    4. Start a fresh `*host.Host` via `host.Start` + `startOne`, record `startedAt[name] = time.Now()`, install it under `hostsMu`, update `e.login.SetHost(name, h)`, and publish `NetworkChanged(name)` + `SpacesChanged()`.
  - Implement `RemoveAccount(ctx, network, accountID string, logoutRemote, deleteChats bool)`:
    1. Find the `*host.Host` for `network`. If a live `*bridgev2.UserLogin` matches `accountID` (`h.Bridge.GetCachedUserLoginByID`), call `ul.Delete(ctx, status.BridgeState{StateEvent: status.StateLoggedOut}, bridgev2.DeleteOpts{LogoutRemote: logoutRemote, DontCleanupRooms: !deleteChats, BlockingCleanup: true})` (`bridgev2/userlogin.go:289`). Otherwise delete the row directly via `h.Bridge.DB.UserLogin.Delete(ctx, networkid.UserLoginID(accountID))` (`bridgev2/database/userlogin.go:88`).
    2. Call `e.Store.RemoveAccountData(ctx, network, accountID, deleteChats)`.
    3. Publish `NetworkChanged(network)` and `SpacesChanged()`.
  - Implement `RefreshSubAccounts(ctx, network, accountID)` by scanning the bridge DB's `portal` (`room_type = 'space'`) and `ghost` (`is_bot = 1`) tables alongside `e.Store.SyncBotSubAccounts(ctx, network, accountID)`.

**Tests:**
- [ ] In `engine_test.go`, test `RestartNetwork` on a running fake bridge (verifying the old connector is stopped, a new connector starts, `startedAt` advances, and concurrent `Status`/`Host` calls under `-race` do not race).
- [ ] Test `RemoveAccount` with `logoutRemote: true` and `logoutRemote: false`, and with `deleteChats: true` and `deleteChats: false`, verifying `LogoutRemote` call count, `user_login` deletion in `<network>.db`, and `rooms`/`login_state` cleanup in `courier.db`.
- [ ] Run `bazel test //apps/desktop/courier/engine/internal/engine/... //apps/desktop/courier/engine/internal/login/... //apps/desktop/courier/engine/internal/networks/...`.

---

## Task 4: Protocol v7 — Bridges, Account Removal, Sub-Accounts, and Diagnostics RPCs

> **Parallel 4.5b note:** 4.5b Task 2 also bumps `protocol.json` from 6 to 7. Whichever branch merges second bumps `protocol` to 8 and updates `hello.json` / `hello-protocol-mismatch.json`.

**Files:**
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Modify: `apps/desktop/courier/protocol/examples/hello.json`
- Modify: `apps/desktop/courier/protocol/examples/hello-protocol-mismatch.json`
- Create: `apps/desktop/courier/protocol/examples/bridges.list.json`
- Create: `apps/desktop/courier/protocol/examples/bridges.restart.json`
- Create: `apps/desktop/courier/protocol/examples/accounts.remove.json`
- Create: `apps/desktop/courier/protocol/examples/accounts.subAccounts.json`
- Create: `apps/desktop/courier/protocol/examples/accounts.setSubAccount.json`
- Create: `apps/desktop/courier/protocol/examples/diagnostics.export.json`
- Modify: `apps/desktop/courier/engine/internal/rpc/server.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/methods.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/server_test.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/conformance_test.go`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ProtocolConformanceTests.swift`

**Interfaces:**
```swift
// In Protocol.swift:
public struct BridgeInfo: Codable, Equatable, Sendable, Identifiable {
    public let network: String
    public let displayName: String
    public let bridgeID: String
    public let modulePath: String
    public let version: String
    public let mautrixVersion: String
    public let state: String
    public let error: String?
    public let message: String?
    public let startedAt: Int64
    public let accounts: [Account]
    public var id: String { network }
}

public struct BridgesResult: Codable, Equatable, Sendable {
    public let bridges: [BridgeInfo]
}

public struct BridgeRestartParams: Encodable, Equatable, Sendable {
    public let network: String
    public init(network: String) { self.network = network }
}

public struct AccountRemoveParams: Encodable, Equatable, Sendable {
    public let network: String
    public let accountID: String
    public let logoutRemote: Bool
    public let deleteChats: Bool
}

public struct SubAccountItem: Codable, Equatable, Sendable, Identifiable {
    public let network: String
    public let accountID: String
    public let subID: String
    public let title: String
    public let avatarURI: String
    public let kind: String // "space" | "bot"
    public let enabled: Bool
    public let showInInbox: ShowInInbox
    public var id: String { "\(network):\(accountID):\(subID)" }
}

public struct SubAccountsParams: Encodable, Equatable, Sendable {
    public let network: String
    public let accountID: String
    public let refresh: Bool?
}

public struct SubAccountsResult: Codable, Equatable, Sendable {
    public let subAccounts: [SubAccountItem]
}

public struct SetSubAccountParams: Encodable, Equatable, Sendable {
    public let network: String
    public let accountID: String
    public let subID: String
    public let enabled: Bool?
    public let showInInbox: ShowInInbox?
}

public struct DiagnosticsExportParams: Encodable, Equatable, Sendable {
    public let roomID: String?
    public let eventID: String?
}

public struct DiagnosticsExportResult: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let schemaVersion: Int
    public let goVersion: String
    public let bridges: [BridgeInfo]
    public let scrubbedStderr: [String]
    public let roomDetails: RoomDiagnostic?
    public let messageDetails: MessageDiagnostic?
}
```

**Steps:**
- [ ] Bump `protocol` in `protocol.json`, `rpc/server.go`, and `Protocol.swift` to `7` (or `8` if 4.5b has landed) and add JSON Schemas and golden examples for `bridges.list`, `bridges.restart`, `accounts.remove`, `accounts.subAccounts`, `accounts.setSubAccount`, and `diagnostics.export`.
- [ ] Implement the 6 handlers in `engine/internal/rpc/methods.go`. In `diagnostics.export`:
  - Read `engine-stderr.log` (if present in data dir) and pass its contents through `logscrub.ScrubStderrExport`.
  - When `roomID` or `eventID` is supplied, return structural metadata (`room_id`, `network`, `is_direct`, `event_id`, `type`, `ts`, `status`, `status_reason` passed through `logscrub.Redact`, `has_media`, `is_redacted`) — never raw message text or sender phone numbers/names.
- [ ] Add corresponding Codable structs to `Protocol.swift` and golden round-trip cases to `conformance_test.go` and `ProtocolConformanceTests.swift`.

**Tests:**
- [ ] Run `bazel test //apps/desktop/courier/engine/internal/rpc/... //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 5: Notification Options, Sound Effects, Delay/Batching, Repeat Unread, OTP Auto-Copy, and Per-Account Overrides

> **Parallel 4.5b note:** 4.5b Task 4 modifies `NotificationCoordinator.swift` and `Notifier.swift` to attach media thumbnails; keep `attachmentURI` handling intact when adding delay/repeat timers and sound selection.

**Files:**
- Modify: `apps/desktop/courier/app/Sources/CourierCore/NotificationPolicy.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/NotificationCoordinator.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/Notifier.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/NotificationPolicyTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/NotificationCoordinatorTests.swift`

**Interfaces:**
```swift
// In NotificationPolicy.swift:
public enum SoundEffectsMode: String, CaseIterable, Codable, Sendable {
    case never, sentOnly, receivedOnly, always
}

public enum NotificationSoundChoice: String, CaseIterable, Codable, Sendable {
    case `default`, none, beeper, sounds, double, dreams, not, marimba, rain, harp, record, spirit
}

public struct AccountNotificationOverride: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var showPreviews: Bool
    public var sound: NotificationSoundChoice?
    public init(enabled: Bool = true, showPreviews: Bool = true, sound: NotificationSoundChoice? = nil)
}

public enum OTPDetector {
    /// Extracts a 4-8 digit OTP/2FA verification code when accompanied by an OTP keyword
    /// ("code", "verification", "OTP", "2FA", "passcode", "security code", "pin").
    public static func extractCode(from text: String) -> String?
}

// Extended NotificationPreferences properties:
// - soundEffectsMode: SoundEffectsMode (default .never)
// - soundEffectsVolume: Double (default 0.7, clamped 0.0...1.0)
// - messageNotificationsEnabled: Bool (default true)
// - messageSound: NotificationSoundChoice (default .default)
// - groupNotificationsEnabled: Bool (default true)
// - groupSound: NotificationSoundChoice (default .default)
// - requestNotificationsEnabled: Bool (default true)
// - notifyWhenInFocus: Bool (default false)
// - notifyOnReaction: Bool (default true)
// - typingNotificationsEnabled: Bool (default false)
// - delaySeconds: Int (allowed: 0, 10, 30, 60, 120, 300; default 0)
// - repeatUnreadMinutes: Int (allowed: 0, 2, 5, 10; default 0)
// - autoCopyOTP: Bool (default false)
// - accountOverrides: [String: AccountNotificationOverride] (keyed by accountKey "network" or "network:loginID")
```

**Steps:**
- [ ] Extend `NotificationPreferences` in `NotificationPolicy.swift` with all properties above, backed by `UserDefaults`, plus `OTPDetector.extractCode(from:)` and `NotificationDecision` evaluation rules:
  - Per-account override (`accountOverrides[accountKey] ?? accountOverrides[network]`): if `enabled == false`, suppress notification (unless `autoCopyOTP` matched an OTP code, which inventory `02` §636 states `"Still notifies even if the chat is muted"`). If `showPreviews == false`, replace notification body with `String(localized: "New message")` and omit media thumbnail attachment.
  - Global `messageNotificationsEnabled` (for `isDirect == true`) and `groupNotificationsEnabled` (for `isDirect == false`).
  - `notifyWhenInFocus`: when `true`, notify even when `Attention.isLooking` is `true` for the open chat.
  - `notifyOnReaction`: gates reaction event notifications (`m.reaction`).
  - `delaySeconds`: when `> 0` and `OTPDetector.extractCode(from: body) == nil`, `NotificationCoordinator` holds the notification for `delaySeconds` and cancels it if the chat is read before the timer fires (`"OTP/2FA codes are always notified immediately"`, `01` §17).
  - `repeatUnreadMinutes`: when `> 0`, schedules a repeat timer after delivery; if the chat is still unread in `InboxModel` when the timer fires, re-posts the notification once.
  - `autoCopyOTP`: when `true` and `OTPDetector.extractCode(from: body)` returns a code, copies the code via an injected `ClipboardSink` (production writes `NSPasteboard.general` with `NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")` and `org.nspasteboard.TransientType`) and adds a `"Copy Code"` action on the notification.
- [ ] In `Notifier.swift`, add:
  - Sound effect playback (`SoundEffectPlayer` using `NSSound` / `AVAudioPlayer` with `soundEffectsVolume`) triggered on sent/received messages according to `soundEffectsMode`.
  - Mapping `NotificationSoundChoice` to `UNNotificationSound` (`.default`, `nil` for `.none`, or `UNNotificationSound(named:)`).
  - `openSystemNotificationSettings()` (`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)`) and `restartNotificationCenter()` (`UNUserNotificationCenter.current().removeAllDeliveredNotifications()` + `Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["NotificationCenter"])`).

**Tests:**
- [ ] In `NotificationPolicyTests.swift` and `NotificationCoordinatorTests.swift`, test:
  - OTP extraction (`"Your Signal verification code is 482-910"`, `"123456 is your login code"`, and non-OTP numbers like `"Meet me at 1400 Pennsylvania Ave"` returning `nil`).
  - Delay batching (`delaySeconds = 30` holds normal message, cancels if marked read at `t = 10s`, delivers at `t = 30s` if still unread; OTP message bypasses delay and delivers at `t = 0s` and copies to `ClipboardSink` when `autoCopyOTP == true` even in a muted chat).
  - Repeat unread (`repeatUnreadMinutes = 2` re-posts at `t = 120s` when unread, does not re-post if read at `t = 60s`).
  - Per-account overrides (`enabled = false`, `showPreviews = false`, custom `sound`), `notifyWhenInFocus`, `notifyOnReaction`, and `SoundEffectsMode` triggers.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 6: Login Item (`SMAppService`), Touch ID App Lock (`LAContext`), and Window Lifecycle Preferences

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/SystemLifecycleModel.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/SystemLifecycleModelTests.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/AppLockOverlay.swift`

**Interfaces:**
```swift
// In SystemLifecycleModel.swift:
public protocol LoginItemService: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public protocol BiometricAuthService: Sendable {
    func canEvaluateBiometrics() -> Bool
    func authenticate(reason: String) async -> Bool
}

@MainActor
public final class SystemLifecycleModel: ObservableObject {
    @Published public private(set) var openAtLogin: Bool
    @Published public var keepMinimizedOnLaunch: Bool
    @Published public var quitOnMainWindowClose: Bool
    @Published public var requireTouchIDOnLaunch: Bool
    @Published public private(set) var isLocked: Bool
    @Published public private(set) var lastError: String?

    public init(defaults: UserDefaults = .standard,
                loginItem: LoginItemService = MACLoginItemService(),
                biometrics: BiometricAuthService = LAContextBiometricService())

    public func setOpenAtLogin(_ enabled: Bool)
    public func lockApp()
    public func unlockWithTouchID() async -> Bool
}
```

**Steps:**
- [ ] Implement `MACLoginItemService` wrapping `SMAppService.mainApp` (`ServiceManagement`, macOS 13.0+): `isEnabled` checks `SMAppService.mainApp.status == .enabled`, `setEnabled(true)` calls `try SMAppService.mainApp.register()`, and `setEnabled(false)` calls `try SMAppService.mainApp.unregister()`.
- [ ] Implement `LAContextBiometricService` wrapping `LAContext` (`LocalAuthentication`): `canEvaluateBiometrics()` checks `context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) || context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)`, and `authenticate(reason:)` evaluates `.deviceOwnerAuthentication` so Touch ID is preferred with macOS passcode fallback.
- [ ] In `SystemLifecycleModel`:
  - When `requireTouchIDOnLaunch == true` at init, start with `isLocked = true` and trigger `unlockWithTouchID()`.
  - `lockApp()` (`command Lock app`, `menu:Beeper Lock App`) sets `isLocked = true`.
  - Provide `shouldHideMainWindowOnLaunch: Bool` (`keepMinimizedOnLaunch`) and `shouldTerminateWhenMainWindowClosed: Bool` (`quitOnMainWindowClose`).
- [ ] Create `AppLockOverlay.swift`: an opaque lock view shown over window content whenever `lifecycle.isLocked == true`, displaying the Courier lock icon, `"Courier is Locked"`, and an `"Unlock with Touch ID…"` button.

**Tests:**
- [ ] In `SystemLifecycleModelTests.swift`, test `setOpenAtLogin` with a fake `LoginItemService` (including registration failure rollback and `lastError`), `requireTouchIDOnLaunch` starting locked and unlocking only when `BiometricAuthService.authenticate` returns `true`, and `lockApp()` toggling `isLocked`.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 7: Dock Menu, Dock Badge Mode, Menu-Bar Tray Icon, and Native Menu Bar

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/DockAndTrayModel.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/DockAndTrayModelTests.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/SpacesModel.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/SpacesModelTests.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/AppDelegate.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MenuBar.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/App.swift`

**Interfaces:**
```swift
// In DockAndTrayModel.swift:
public enum DockBadgeMode: String, CaseIterable, Codable, Sendable {
    case unreadChats // default: unmuted unread chats in inbox (attention_chats)
    case allChats    // all unread chats in inbox (unread_chats)
    case none        // no Dock badge ("")
}

public struct DockChatItem: Equatable, Sendable, Identifiable {
    public let roomID: String
    public let title: String // truncated to 40 characters per inventory 02 §3.2
    public var id: String { roomID }
}

public struct DockMenuModel: Equatable, Sendable {
    public let unreadChats: [DockChatItem] // up to 5
    public let recentChats: [DockChatItem] // up to 5
    public var isEmpty: Bool { unreadChats.isEmpty && recentChats.isEmpty }

    public static func build(isLocked: Bool,
                             inboxRows: [InboxRow],
                             recentlyViewedRoomIDs: [String],
                             currentRoomID: String?) -> DockMenuModel
}
```

**Steps:**
- [ ] Implement `DockBadgeMode` (`setting:appearance Dock badge count`) and `DockMenuModel.build` in `DockAndTrayModel.swift` matching inventory `02` §3.2:
  - When `isLocked == true`, return empty `unreadChats` and `recentChats`.
  - `unreadChats`: up to 5 unread chats from `inboxRows` (`unread > 0 && !lowPriority && !hidden`), newest first, title truncated to 40 characters (`title.count > 40 ? String(title.prefix(39)) + "…" : title`).
  - `recentChats`: up to 5 chats from `recentlyViewedRoomIDs` (`InboxModel` viewing history), excluding `currentRoomID`, any chat already in `unreadChats`, and hidden chats.
  - Add `showMenuBarIcon: Bool` (`setting:appearance Show menu bar icon`, default `true`, stored in `UserDefaults`).
- [ ] In `SpacesModel.swift`, compute `badgeCount(of:mode:)` using `DockBadgeMode` (`.unreadChats` → `attentionChats`, `.allChats` → `unreadChats`, `.none` → `0`).
- [ ] In `AppDelegate.swift`:
  - Implement `applicationDockMenu(_ sender: NSApplication) -> NSMenu?` building the two disabled section headers `"Unread Chats"` and `"Recent Chats"` and items that focus the main window and call `inbox.select(roomID)` (and unlock first if locked).
  - Manage the `NSStatusItem` (`NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`) when `showMenuBarIcon == true`: template icon with tooltip `"Courier"`, left-click shows/focuses windows if hidden/unfocused or pops up the menu when focused, right-click pops up the menu (`"Minimize to Menu Bar"` `⌘⌥Q` when windows are visible, `"Quit Courier"` `⌘Q`).
  - Wire `minimizeToMenuBar()` (`⌘⌥Q`, `hotkey Minimize To Menu Bar`) to hide all app windows (`NSApp.hide(nil)`), and update `applicationShouldTerminateAfterLastWindowClosed` to return `lifecycle.quitOnMainWindowClose`.
- [ ] In `MenuBar.swift`, complete the native macOS menus (`02` §3.1):
  - **Application (`Beeper` / `Courier`):** `About Courier` (opens Settings → About), `Accounts…` (opens Settings → Accounts), `Preferences…` (`⌘,`), `Search…` (`⌘K`), `Lock App` (`command Lock app`), `Minimize to Menu Bar` (`⌘⌥Q`).
  - **File:** `Open…` (`⌘O`), `New Chat` (`⌘N`), `Open Chat in New Window`, `Close Window` (`⌘W`), `Close All` (`⌘⌥W`).
  - **View:** `Show/Hide Space Bar` (`⌘S`), `Show/Hide Sidebar` (`⌘⌥S`).
  - **Help:** `Report a Problem…` (`⌘⇧P`), `Keyboard Shortcuts` (`⌘/`), `Privacy & Security`, `Changelog`, `Open Beeper Help`, `Open Beeper.com`, `Follow @Beeper on X`.

**Tests:**
- [ ] In `DockAndTrayModelTests.swift` and `SpacesModelTests.swift`, test:
  - `DockMenuModel.build` when locked (empty), with >5 unread chats (capped at 5, low-priority/hidden excluded), with recent chats (current chat and unread chats deduplicated, 40-char truncation).
  - `DockBadgeMode` (`.unreadChats`, `.allChats`, `.none`) badge counts.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 8: Detached Chat, Space, and Thread Windows (`Open in New Window`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/DetachedWindowModel.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/DetachedWindowModelTests.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/DetachedWindows.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/InboxPreferences.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/InboxPreferencesTests.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatContextMenu.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SpaceBar.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ThreadPane.swift`

**Interfaces:**
```swift
// In DetachedWindowModel.swift:
public enum DetachedWindowTarget: Hashable, Codable, Sendable, Identifiable {
    case chat(roomID: String)
    case space(spaceID: String)
    case thread(roomID: String, rootEventID: String)

    public var id: String { ... }
}

@MainActor
public final class DetachedWindowRegistry: ObservableObject {
    @Published public private(set) var openTargets: [DetachedWindowTarget] = []
    public var onOpenWindow: ((DetachedWindowTarget) -> Void)?

    public func open(_ target: DetachedWindowTarget)
    public func close(_ target: DetachedWindowTarget)
}
```

**Steps:**
- [ ] In `InboxPreferences.swift`, add `.openInNewWindow` to `DoubleClickChatAction` (`setting:appearance On double-clicking a chat`: `Open in New Window`, `Archive`, `Mark Read/Unread`, `Mute/Unmute`, `Move to Low Priority`, `Do Nothing`).
- [ ] Create `DetachedWindowModel.swift` and `DetachedWindows.swift`:
  - `DetachedWindowManager` opens reuse-aware `NSWindow` instances keyed by `DetachedWindowTarget` (if a window for `.chat(roomID)` is already open, `makeKeyAndOrderFront` brings it forward instead of opening a duplicate).
  - `.chat(roomID)` hosts an independent `ConversationModel` + `ComposerModel` + `ConversationView` for `roomID`.
  - `.space(spaceID)` (`command Open space in new window`) hosts a standalone `InboxModel` (pre-selected to `spaceID`) + `MainWindow` split view.
  - `.thread(roomID, rootEventID)` (`component ThreadedRepliesBrowserWindow.tsx`) hosts a standalone `ThreadPane` window for that thread root, triggered by an `"Open in New Window"` button in `ThreadPane.swift`'s header.
- [ ] Wire `"Open in New Window"` in `ChatContextMenu.swift`, `SpaceBar.swift` (both account and built-in space right-click menus), `MenuBar.swift` (`menu:File Open Chat in New Window`), and double-clicking an inbox row in `MainWindow.swift` when `doubleClickChat == .openInNewWindow`.

**Tests:**
- [ ] In `DetachedWindowModelTests.swift` and `InboxPreferencesTests.swift`, test `DetachedWindowRegistry` deduplication, opening/closing `.chat`, `.space`, and `.thread` targets, and `DoubleClickChatAction.openInNewWindow` persistence.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 9: Hotkey Registry, Shortcut Recorder, and Keyboard Shortcuts Sheet (`⌘/`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/HotkeyRegistry.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/HotkeyRegistryTests.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/HotkeysSettingsPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/KeyboardShortcutsSheet.swift`

**Interfaces:**
```swift
// In HotkeyRegistry.swift:
public struct KeyChord: Codable, Equatable, Hashable, Sendable {
    public var key: String // e.g. "k", "f", "e", "enter", "tab", "up", "down", "[", "]"
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    /// Formats as macOS symbols (e.g. "⌘⇧E", "⌃⌥→", "⌘,") per inventory 02 §2.1.
    public var symbols: String { ... }
    /// True when at least one of command, control, option, or shift is set (or key is F1-F12).
    public var hasRequiredModifier: Bool { ... }
}

public struct HotkeyDefinition: Equatable, Sendable, Identifiable {
    public let id: String          // ledger item name, e.g. "Chat: Toggle Archive"
    public let title: String
    public let category: String    // "General", "Navigation", "Chat", "Message", "Composer"
    public let defaultChords: [KeyChord]
    public let supportsGlobal: Bool // true for "Focus App" and "Focus App and Command Bar"
}

@MainActor
public final class HotkeyRegistry: ObservableObject {
    public static let allDefinitions: [HotkeyDefinition]
    @Published public var searchQuery: String = ""
    @Published public private(set) var overrides: [String: [KeyChord]]
    @Published public private(set) var disabledIDs: Set<String>
    @Published public private(set) var globalIDs: Set<String>

    public func chords(for id: String) -> [KeyChord]
    public func record(_ chord: KeyChord, for id: String) -> Result<Void, HotkeyConflictError>
    public func setEnabled(_ enabled: Bool, for id: String)
    public func revert(id: String)
    public func revertAll()
    public func applyTextsAppPreset()
}
```

**Steps:**
- [ ] Populate `HotkeyRegistry.allDefinitions` in `HotkeyRegistry.swift` with the full shortcut catalog from inventory `02` §2.2 / Part B Keyboard table (`Chat: Archive All Read` through `Send Message`, including `Focus App`, `Focus App and Command Bar`, `Keyboard Shortcuts` `⌘/`, `Minimize To Menu Bar` `⌘⌥Q`, `Report a Problem` `⌘⇧P`, `Settings` `⌘,`, etc.).
- [ ] Enforce the recorder validation rules from `01` §17 (`HotkeysPrefsSubView.tsx`):
  - Reject bare single-character keys without a modifier (`"You must use a modifier key like Ctrl, Shift or Option/Alt"`).
  - Reject chords already bound to another enabled action (`"%1$s is already used by %2$s"`).
  - Support `"Revert all"` and `"Switch to Texts.app keybindings"` preset.
- [ ] Build `HotkeysSettingsPane.swift` (`HotkeysPrefsSubView.tsx`, `Key.tsx`) with `"Search hotkeys..."`, per-row enable toggle, `"Record Shortcut"` pill button, `"Global"` toggle on `Focus App` and `Focus App and Command Bar`, `"Revert all"`, and `"Switch to Texts.app keybindings"`.
- [ ] Build `KeyboardShortcutsSheet.swift` (`⌘/`, `hotkey Keyboard Shortcuts`, `command Show keyboard shortcuts`, `menu:Help Keyboard Shortcuts`): a multi-column reference sheet grouping active shortcuts by category with `KeyView` (`Key.tsx`) keycap badges.

**Tests:**
- [ ] In `HotkeyRegistryTests.swift`, test symbol formatting (`⌘⇧E`, `⌃Tab`, `⌘/`), modifier validation error, conflict detection error (`"%1$s is already used by %2$s"`), search filtering, `applyTextsAppPreset()`, and `revertAll()` persistence.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 10: Accounts & Bridges Model, Account Pane, and Bridges Pane

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/AccountsAndBridgesModel.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/AccountsAndBridgesModelTests.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/AccountsSettingsPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/BridgesSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SpaceBar.swift`

**Interfaces:**
```swift
// In AccountsAndBridgesModel.swift:
public protocol DockTileService: Sendable {
    func isAppInDock(bundleIdentifier: String) -> Bool
    func removeAppFromDock(bundleIdentifier: String) -> Bool
}

@MainActor
public final class AccountsAndBridgesModel: ObservableObject {
    @Published public private(set) var bridges: [BridgeInfo] = []
    @Published public private(set) var subAccountsByKey: [String: [SubAccountItem]] = [:]
    @Published public var selectedAccountKey: String? // "network:accountID"
    @Published public var expandedBridgeNetworks: Set<String> = []
    @Published public private(set) var busyNetworks: Set<String> = []
    @Published public private(set) var lastToast: String?
    @Published public private(set) var lastError: String?

    public static func officialDockBundleID(for network: String) -> String?

    public func refresh() async
    public func restartBridge(network: String) async
    public func removeAccount(network: String, accountID: String, logoutRemote: Bool, deleteChats: Bool) async
    public func loadSubAccounts(network: String, accountID: String, forceRefresh: Bool) async
    public func updateSubAccount(network: String, accountID: String, subID: String, enabled: Bool?, showInInbox: ShowInInbox?) async
    public func removeOfficialAppFromDock(network: String) -> Bool
    public func bridgeJSON(for network: String) -> String?
}
```

**Steps:**
- [ ] Implement `AccountsAndBridgesModel` in `AccountsAndBridgesModel.swift`:
  - Subscribes to `appModel.onChange` for `.bridge` and `.spaces` events and calls `bridges.list`.
  - `restartBridge(network:)` calls `bridges.restart` and announces `"Bridge restarted"`.
  - `removeAccount(network:accountID:logoutRemote:deleteChats:)` calls `accounts.remove`, refreshes `spaces` and `bridges`, and clears `selectedAccountKey` if it was removed.
  - `officialDockBundleID(for:)` maps `"whatsapp"` → `"net.whatsapp.WhatsApp"`, `"signal"` → `"org.whispersystems.signal-desktop"`, `"telegram"` → `"ru.keepcoder.Telegram"`, `"slack"` → `"com.tinyspeck.slackmacgap"`, `"gmessages"` → `nil`. `MACDockTileService` inspects and removes the matching entry from `UserDefaults(suiteName: "com.apple.dock")` `"persistent-apps"` and restarts the Dock (`killall Dock`).
- [ ] Build `AccountsSettingsPane.swift` (`AccountPrefsSubView.tsx`, `AccountActions.tsx`, `AccountListItemPure.tsx`, `AccountNotificationPrefs.tsx`, `AccountDisconnectedBanner.tsx`, `OtherAccounts.tsx`):
  - **Accounts list view** (`command Accounts`): lists all connected accounts across networks with on-device indicator (`DeviceIndicator`), live state badge, error banner with `Reconnect` (`AccountDisconnectedBanner.tsx`), `"Add Account…"` button (opens `SignInWindow`), and right-click context menu (`02` §3.4.4).
  - **Single Account detail sub-view** (`command Account`):
    - Status header (`OK` / `DISCONNECTED` / `BAD_CREDENTIALS`) with `Reconnect` or `Retry` button.
    - `"Show in Inbox"` picker (`All Messages`, `Only DMs`, `None` — wired to `SpacesModel.setShowInInbox`).
    - **Notifications section** (`AccountNotificationPrefs.tsx`): `Enable notifications`, `Show message previews`, and `Notification sound` override for this account.
    - **Dock section** (when `officialDockBundleID(for:)` is non-nil and present in Dock): `"Remove official <Network> app from Dock"` button.
    - **Sub-Accounts section**: lists sub-accounts (`SubAccountItem`) with on/off toggle, per-sub-account `Show in Inbox` picker, and `"Refresh List"` button (`accounts.subAccounts` with `refresh: true`).
    - **Danger zone**: `"Remove Account…"` button opening a confirmation sheet with checkboxes `"Also sign out on <Network>"` (default on for WhatsApp/Signal/Telegram/Google Messages; default off for Slack with explanation) and `"Delete local chat history from this Mac"` (default on).
- [ ] Build `BridgesSettingsPane.swift` (`command Bridges`, `02` §1.7 "Bridges pane contents"):
  - Lists the 5 on-device bridges with network icon, state badge, module version, and account count (`"%d account"`).
  - Clicking a bridge row expands it to show `Created:` (started time), `Version:` (`modulePath@version`), `Reason:` / `Info:`, and the account rows under it.
  - `"Bridge Actions"` menu on each bridge row: `"Restart Bridge"` (with confirmation prompt), `"Copy bridge ID"`, `"Copy bridge info as JSON"`, and `"Add an account"`.
  - Per-account menu under each bridge: `"Account Settings…"`, `"Copy Account ID"`, `"Copy Remote ID"`.
- [ ] Update `SpaceBar.swift` account context menu (`02` §3.4.4) to add `"Open in New Window"`, `"Account Settings…"`, `"Remove Account…"`, and `"Developer"` submenu (`"Copy Account ID"`, `"Copy Bridge ID"`, `"Copy Info as JSON"`, `"Restart Bridge"`).

**Tests:**
- [ ] In `AccountsAndBridgesModelTests.swift`, test `refresh()`, `restartBridge`, `removeAccount` (including Slack vs WhatsApp default `logoutRemote` flags), `loadSubAccounts` / `updateSubAccount`, `bridgeJSON`, and `removeOfficialAppFromDock` with a fake `DockTileService`.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 11: Report a Problem Local Bundle & Message Details Copy

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/ProblemReportModel.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/ProblemReportModelTests.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/ProblemReportSheet.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/MessageActionsModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/MessageMenu.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageMenu.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/MessageActionsModelTests.swift`

**Interfaces:**
```swift
// In ProblemReportModel.swift:
@MainActor
public final class ProblemReportModel: ObservableObject {
    @Published public var descriptionText: String = ""
    @Published public var includeMessageDetails: Bool = false
    @Published public var attachedFileURLs: [URL] = []
    @Published public private(set) var diagnostics: DiagnosticsExportResult?
    @Published public private(set) var scrubbedSupervisorLines: [String] = []
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var savedBundleURL: URL?
    @Published public private(set) var errorText: String?

    public let contextRoomID: String?
    public let contextEventID: String?

    public func loadDiagnostics() async
    /// Writes summary.json, bridges.json, stderr-scrubbed.log, and any user-selected attachments
    /// into a local directory or .zip archive at destinationURL. Never makes a network call.
    public func writeBundle(to destinationURL: URL) throws
}
```

**Steps:**
- [ ] Implement `ProblemReportModel` in `ProblemReportModel.swift`:
  - `loadDiagnostics()` calls `diagnostics.export` (passing `roomID` and `eventID` only when `includeMessageDetails == true`) and filters `EngineSupervisor.recentErrorOutput` through a Swift mirror of Ruling 10 (`StderrExportFilter.scrub(_:)`) so both engine-side and supervisor-captured stderr lines obey Ruling 10.
  - `writeBundle(to:)` writes a local diagnostic bundle containing `report.json` (user description, app version, macOS version, protocol/schema versions, bridge states, and optional scrubbed room/message metadata), `stderr-scrubbed.log` (only the Ruling 10 scrubbed JSON lines and redacted Go stack frames), and any user-attached screenshot/video files.
- [ ] Add `.copyMessageDetails` (inventory `02` §3.4.2) and `.reportProblem` to `MessageMenu.swift` and `MessageActionsModel.swift`:
  - `"Copy Message Details"` copies a scrubbed JSON summary (`event_id`, `room_id`, `network`, `type`, `ts`, `status`, `status_reason`) to the clipboard and announces `"Message details copied"`.
  - `"Report a Problem"` on a message or chat pre-fills `contextRoomID` / `contextEventID` and opens `ProblemReportSheet`.
- [ ] Build `ProblemReportSheet.swift` (`command Report a problem`, `hotkey Report a Problem` `⌘⇧P`, `menu:Help Report a Problem`):
  - Text area (`"Describe the issue..."`), `"Attach screenshot or video…"` (`NSOpenPanel`), `"Include Message Details"` / `"Include Latest Message Details"` toggle (`CopyableDataViewer.tsx` preview of the exact scrubbed JSON and `stderr-scrubbed.log` lines that will be saved), and `"Save Problem Report…"` (`NSSavePanel`, default filename `courier-problem-report-<YYYY-MM-DD-HHmmss>.zip`).

**Tests:**
- [ ] In `ProblemReportModelTests.swift` and `MessageActionsModelTests.swift`, test:
  - `loadDiagnostics()` with `includeMessageDetails` off vs on.
  - `writeBundle(to:)` verifying the written files contain zero raw panic payloads, zero `/Users/<name>` paths, and zero message bodies.
  - `"Copy Message Details"` copying scrubbed JSON to `Pasteboard`.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 12: Two-Column Settings Shell (`⌘,`), Settings Search (`SearchSuggestions`), General, Appearance, Quick Replies & About Panes

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/SettingsSearchModel.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/SettingsSearchModelTests.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/SettingsWindow.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/GeneralSettingsPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/NotificationsSettingsPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/QuickRepliesSettingsPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/AboutSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerPreferences.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ComposerPreferencesTests.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/CommandSet.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/CommandSetTests.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/InboxSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessagesSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/App.swift`

**Interfaces:**
```swift
// In SettingsSearchModel.swift:
public enum SettingsPaneID: String, CaseIterable, Codable, Sendable, Identifiable {
    case general, appearance, notifications, accounts, hotkeys, quickReplies, bridges, about
    public var id: String { rawValue }
    public var title: String { ... }
    public var symbolName: String { ... }
}

public struct SettingDefinition: Equatable, Sendable, Identifiable {
    public let id: String        // e.g. "notifications.delay"
    public let pane: SettingsPaneID
    public let section: String
    public let title: String     // exact inventory label, e.g. "Delay notifications for"
    public let keywords: [String]
    public let badge: SettingBadge? // .labs ("Experimental and subject to change")
}

@MainActor
public final class SettingsNavigationModel: ObservableObject {
    @Published public var selectedPane: SettingsPaneID = .general
    @Published public var searchQuery: String = ""
    @Published public var highlightedSettingID: String?

    public var suggestions: [SettingDefinition] { ... }
    public func jump(to setting: SettingDefinition)
    public func openPane(_ pane: SettingsPaneID, accountKey: String? = nil)
}
```

**Steps:**
- [ ] In `ComposerPreferences.swift` (and `ComposerView.swift`), add the two composer button settings carried from 4.3 (`apps/desktop/courier/docs/m4-acceptance.md:591`):
  - `PrimaryComposerButton` (`setting:appearance Primary composer button`: `.emojiPicker`, `.gifPicker`, `.addAttachment`, `.sendLater`, `.none`; default `.emojiPicker`).
  - `SecondaryComposerButton` (`setting:appearance Secondary composer button`: `.recordAudio`, `.gifPicker`, `.addAttachment`, `.sendLater`, `.none`; default `.recordAudio`).
  - `timeFormat`: `TimeFormatPreference` (`setting:general Time Format`: `.system`, `.twelveHour`, `.twentyFourHour`).
- [ ] Create `SettingsSearchModel.swift` (`preference-definitions.tsx`, `SearchSuggestions.tsx`, `PreferenceTags.tsx`):
  - Catalogs every setting across all 8 panes (`General`, `Appearance`, `Notifications`, `Accounts`, `Hotkeys`, `Quick Replies`, `Bridges`, `About`).
  - Typing in `"Search Settings"` (`⌘F` inside Settings) shows matching `SettingDefinition` suggestions (`"Pane → Setting"`); selecting one switches `selectedPane` and scrolls/highlights that control (`highlightedSettingID`).
- [ ] Build `SettingsWindow.swift` (`PrefsPanes.tsx`, `PrefOption.tsx`, `PrefsControls.tsx`, `DynamicPreferencesRenderer.tsx`, `PrefsActionPrompt.tsx`):
  - Left column (`PrefsLeftPane`): `"Search Settings"` field with `SearchSuggestions` dropdown + category rows (`General`, `Appearance`, `Notifications`, `Accounts` with connected account count badge, `Hotkeys`, `Quick Replies`, `Bridges`, `About`).
  - Right column (`PrefsRightPane`): renders the selected pane:
    - `GeneralSettingsPane.swift`: Incognito mode, Show recipients I'm typing, Reminder defaults + **Time Suggestions editor** (add/remove/reset presets on `ReminderPresets`, carried from 4.1 `m4-acceptance.md:195`), Archive rules + bulk archive older chats, After archive / After mark as read, Double-click message action, Undo send window + click pending to undo, Include timestamps on `⌘C`, Emoji/GIF/Voice note & Downloads controls (shared with 4.5b Tasks 7–10), `Auto copy OTP/2FA codes`, Press `↑` in composer, Default for send later, Login Item (`Open Beeper at login`, `Keep Beeper minimized on launch`, `Quit Beeper when closing the main window`), `Require Touch ID authentication on launch`, and `Time Format` (12-hour / 24-hour).
    - `AppearanceSettingsPane` (consolidating `InboxSettingsPane.swift` and `MessagesSettingsPane.swift`): Chat list appearance (`Show sidebar`, `Use regular style for pinned chats`, `Show number of unread messages`, `Show message previews`, `Show network icons`, `Colorize network icons`, hover action, double-click chat action including `Open in New Window`), Conversation view (`Show message timestamps`, `Hide deleted messages`, `Show membership events`, quick reactions), Composer (`Enable spellcheck`, `Show formatting menu`, `Disable link previews in outgoing messages`, `Primary composer button`, `Secondary composer button`), and System (`Show menu bar icon`, `Dock badge count`: None / All chats / Unread chats).
    - `NotificationsSettingsPane.swift`: all controls from Task 5 + `"Open Notifications in System Settings"` and `"Restart Notification Center"` buttons.
    - `AccountsSettingsPane.swift` & `BridgesSettingsPane.swift`: from Task 10.
    - `HotkeysSettingsPane.swift`: from Task 9.
    - `QuickRepliesSettingsPane.swift` (`QuickRepliesPrefsSubView.tsx`): create, edit, and delete saved replies (`QuickReplies`), with template variable guide (`{first_name}`, `{last_name}`, `{full_name}`, `{username}`, `{phone_number}`, `{email}`).
    - `AboutSettingsPane.swift`: Courier version & build info, `"View Changelog"`, `"Report a Problem…"` (`⌘⇧P`), `"Keyboard Shortcuts"` (`⌘/`), `"Privacy & Security"`, and `"Legal Notices"` (MIT/MPL-2.0/AGPL-3.0 notices for embedded bridges).
- [ ] Update `CommandSet.swift` so `settings`, `general`, `appearance`, `notifications`, `accounts`, `account`, `hotkeys`, `quickReplies`, `bridges`, `about`, `help`, `lockApp`, `reportProblem`, `restartNotificationCenter`, `openSpaceInNewWindow`, and `showKeyboardShortcuts` are registered and wired to their handlers.

**Tests:**
- [ ] In `SettingsSearchModelTests.swift`, `ComposerPreferencesTests.swift`, and `CommandSetTests.swift`, test:
  - `SettingsNavigationModel` search suggestions for queries like `"touch id"`, `"otp"`, `"delay"`, `"dock"`, `"composer"`, and `jump(to:)` switching panes.
  - `PrimaryComposerButton`, `SecondaryComposerButton`, and `TimeFormatPreference` persistence.
  - `CommandSet` routing for all new 4.6 commands.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

## Task 13: Light & Dark PNG View Snapshot Tests and Acceptance Documentation (`m4-acceptance.md`)

**Files:**
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`
- Modify: `apps/desktop/courier/docs/m4-acceptance.md`

**Steps:**
- [ ] In `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`, add light and dark PNG snapshot tests (`assertLightAndDarkSnapshot`) for:
  1. `testSettingsWindowGeneralAndSearchSnapshots`: Two-column `SettingsWindow` on the `General` pane (showing Login Item, Touch ID lock, Time Suggestions editor, Auto-copy OTP) and with `"Search Settings"` showing `SearchSuggestions`.
  2. `testSettingsWindowAppearanceAndNotificationsSnapshots`: `Appearance` pane (Primary/Secondary composer buttons, Dock badge count, Show menu bar icon) and `Notifications` pane (Sound effects + volume, Delay notifications, Repeat unread, System Settings / Restart Notification Center buttons).
  3. `testAccountsAndAccountDetailPaneSnapshots`: `AccountsSettingsPane` list view and single `Account` detail view (with `AccountDisconnectedBanner`, `Show in Inbox`, per-account notification overrides, `Remove official WhatsApp app from Dock`, `Sub-Accounts` list with `Refresh List`, and `Remove Account…` confirmation sheet).
  4. `testBridgesSettingsPaneSnapshots`: `BridgesSettingsPane` with an expanded bridge row showing version, started time, accounts, and Bridge Actions menu.
  5. `testHotkeysPaneAndShortcutsSheetSnapshots`: `HotkeysSettingsPane` (with recording state and a conflict warning banner) and `KeyboardShortcutsSheet` (`⌘/`).
  6. `testQuickRepliesAndAboutPanesSnapshots`: `QuickRepliesSettingsPane` and `AboutSettingsPane`.
  7. `testProblemReportSheetAndAppLockOverlaySnapshots`: `ProblemReportSheet` (with scrubbed stderr preview and message details toggle) and `AppLockOverlay` (Touch ID lock screen).
- [ ] Update `apps/desktop/courier/docs/m4-acceptance.md`:
  - Add section `## Part 4.6: settings, notifications and the Bridges pane` with plain-English acceptance steps and the complete 4.6 ledger table.
  - Mark every item carried from 4.1, 4.2, 4.3, 4.4, and 4.5a to 4.6 as delivered in 4.6.
- [ ] Run full build, test, lint, and format checks:
  - `bazel test //apps/desktop/courier/...`
  - `aspect lint //apps/desktop/courier/...`

**Tests:**
- [ ] Verify all light and dark PNG snapshots render non-empty, distinct light/dark images and pass `bazel test //apps/desktop/courier/app:CourierViewTests`.

---

## Task 14: Owner's By-Hand Day

**Steps:**
- [ ] **1. Settings window (`⌘,`) & search (`⌘F`):**
  - Press `⌘,` to open the two-column Settings window. Press `⌘F`, type `"touch id"`, `"delay"`, and `"composer"`, and verify the search suggestions dropdown jumps directly to the matching pane and highlights the setting.
  - In **General**, add a custom preset in **Time suggestions**, open a chat's **Remind Me** (`⌘L`) menu, and confirm the new preset appears; click **Reset** in Settings to restore defaults.
  - In **Appearance**, change **Primary composer button** and **Secondary composer button** and confirm the composer's right-hand buttons update immediately.
- [ ] **2. Notifications, OTP bypass & per-account overrides:**
  - In **Notifications**, set **Sound effects** to `Always`, set **Delay notifications for** to `30 seconds`, and turn on **Auto copy OTP/2FA codes** (in General).
  - Send yourself a normal message from a second device while Courier is in the background: confirm the notification waits 30 seconds (and cancels if you read the chat within 30 seconds).
  - Send yourself `"Your verification code is 849201"`: confirm the notification arrives **immediately** (bypassing the 30-second delay) and `849201` is copied to your clipboard.
  - Open **Settings → Accounts → <your account>**, turn off **Show message previews**, and confirm the next notification from that account reads `"New message"` without message text.
  - Click **Restart Notification Center** and **Open Notifications in System Settings** and verify both work.
- [ ] **3. Bridges pane, Restart Bridge, Sub-Accounts & Remove Account:**
  - Open **Settings → Bridges**, expand **WhatsApp** / **Slack** / **Telegram**, verify the pinned module version (`v0.2609.0` / `v0.2609.1`) and start time are shown, and click **Bridge Actions → Restart Bridge**. Confirm the bridge stops, restarts within a few seconds, and reconnects without restarting Courier.
  - Open **Settings → Accounts → Slack (or Telegram)**, click **Refresh List** under **Sub-Accounts**, toggle a bot or workspace sub-account off, and confirm its chats leave the inbox.
  - Link a test secondary account, click **Remove Account…**, and verify it disconnects and disappears from the space bar and Accounts list.
- [ ] **4. Report a Problem (`⌘⇧P`) & Ruling 10 verification:**
  - Right-click a message and choose **Copy Message Details**; paste into a text editor and confirm only scrubbed structural JSON (no message text or phone number) was copied.
  - Press `⌘⇧P` to open **Report a Problem**, inspect the preview of `stderr-scrubbed.log` and `report.json`, save the `.zip` bundle to Desktop, unzip it, and verify no `/Users/<your-username>` path, token, phone number, or message body appears anywhere in the bundle.
- [ ] **5. Login Item, Touch ID Lock, Dock Menu, Tray Icon & Detached Windows:**
  - Toggle **Open Courier at login** in **Settings → General** and verify Courier appears in **macOS System Settings → General → Login Items**.
  - Turn on **Require Touch ID authentication on launch** and choose **Courier → Lock App** from the menu bar: verify the lock overlay hides all chats, right-clicking the Dock icon shows no chat names, and Touch ID unlocks the app.
  - Right-click the Dock icon while unlocked: verify **Unread Chats** (up to 5) and **Recent Chats** (up to 5) appear and clicking one opens that chat.
  - Press `⌘⌥Q` (**Minimize to Menu Bar**), then click the Courier menu-bar icon to restore the window.
  - Choose **File → Open Chat in New Window**, right-click a space and choose **Open in New Window**, and click **Open in New Window** in a thread header: verify all three open in independent windows.
  - Press `⌘/` to view the **Keyboard Shortcuts** sheet, then rebind a shortcut in **Settings → Hotkeys** and verify the new key chord works.

---

## Ledger Coverage (99 rows)

Every row below exists verbatim as `anchor\titem` in `docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv`:

- `component	./sentry/crash-reporter.ts`
- `component	./sentry/init-sentry-electron.ts`
- `component	./sentry/init-sentry-nonbrowser.ts`
- `component	AccountActions.tsx`
- `component	AccountDisconnectedBanner.tsx`
- `component	AccountListItemPure.tsx`
- `component	AccountNotificationPrefs.tsx`
- `component	AccountPrefsSubView.tsx`
- `component	AccountsBanner.tsx`
- `component	CopyableDataViewer.tsx`
- `component	CopyableField.tsx`
- `component	DeleteAccountModal.tsx`
- `component	DeleteAccountPrompt.tsx`
- `component	DynamicPreferencesRenderer.tsx`
- `component	ErrorBoundary.tsx`
- `component	ErrorRenderer.tsx`
- `component	HelpHubBrowserWindow.tsx`
- `component	HotkeysPrefsSubView.tsx`
- `component	Key.tsx`
- `component	OtherAccounts.tsx`
- `component	PrefOption.tsx`
- `component	PreferenceTags.tsx`
- `component	PrefsActionPrompt.tsx`
- `component	PrefsControls.tsx`
- `component	PrefsPanes.tsx`
- `component	QuickRepliesPrefsSubView.tsx`
- `component	SearchSuggestions.tsx`
- `component	ThreadedRepliesBrowserWindow.tsx`
- `component	preference-definitions.tsx`
- `component	settings.tsx`
- `command	Show settings`
- `command	Show keyboard shortcuts`
- `command	Lock app`
- `command	Report a problem`
- `command	Settings`
- `command	Account`
- `command	Accounts`
- `command	General`
- `command	Appearance`
- `command	Notifications`
- `command	Hotkeys`
- `command	Quick Replies`
- `command	Bridges`
- `command	About`
- `command	Help`
- `command	Open space in new window`
- `command	Restart macOS Notification Center`
- `hotkey	Focus App`
- `hotkey	Focus App and Command Bar`
- `hotkey	Keyboard Shortcuts`
- `hotkey	Minimize To Menu Bar`
- `hotkey	Quit App`
- `hotkey	Report a Problem`
- `hotkey	Settings`
- `setting:appearance	On double-clicking a chat`
- `setting:appearance	Primary composer button`
- `setting:appearance	Secondary composer button`
- `setting:appearance	Show menu bar icon`
- `setting:appearance	Dock badge count`
- `setting:general	Auto copy OTP/2FA codes`
- `setting:general	Open Beeper at login`
- `setting:general	Keep Beeper minimized on launch`
- `setting:general	Quit Beeper when closing the main window`
- `setting:general	Require Touch ID authentication on launch`
- `setting:general	Time Format`
- `setting:notifications	Sound effects`
- `setting:notifications	Message notifications`
- `setting:notifications	Sound`
- `setting:notifications	Group message notifications`
- `setting:notifications	Message request notifications`
- `setting:notifications	Notify when app is in focus`
- `setting:notifications	Notify when someone reacts to a message`
- `setting:notifications	Notify when someone starts typing (supported platforms only)`
- `setting:notifications	Delay notifications for`
- `setting:notifications	Repeat notification if still unread after`
- `menu:Beeper	About Beeper`
- `menu:Beeper	Accounts…`
- `menu:Beeper	Preferences`
- `menu:Beeper	Search…`
- `menu:Beeper	Services`
- `menu:Beeper	Hide Beeper`
- `menu:Beeper	Hide Others`
- `menu:Beeper	Show All`
- `menu:Beeper	Lock App`
- `menu:Beeper	Quit Beeper`
- `menu:File	Open…`
- `menu:File	New Chat`
- `menu:File	Close Window`
- `menu:File	Close All`
- `menu:File	Open Chat in New Window`
- `menu:View	Hide Space Bar`
- `menu:View	Hide Sidebar`
- `menu:Help	Report a Problem`
- `menu:Help	Open Beeper Help`
- `menu:Help	Open Beeper.com`
- `menu:Help	Follow @Beeper on X`
- `menu:Help	Changelog`
- `menu:Help	Privacy & Security`
- `menu:Help	Keyboard Shortcuts`

---

## Appendix: Bridge Source Verification Commands

Run these commands to verify every bridge `file:line` citation in this plan against the pinned modules in `~/go/pkg/mod`:

```bash
# 1. bridgev2 Stop, StopWithTimeout, UserLogin.Delete, UserLoginQuery.Delete, and StartLogins:
grep -rn "func (br \*Bridge) Stop\|func (br \*Bridge) Start\|func (ul \*UserLogin) Delete\|func (uq \*UserLoginQuery) Delete\|func (br \*Bridge) unlockedLoadUserLoginsByMXID" \
  ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/bridgev2/

# 2. Per-connector LoadUserLogin, Disconnect, Stop, and LogoutRemote:
grep -rn "func .*LoadUserLogin\|func .*LogoutRemote\|func .*Disconnect\|func .*Stop(" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/connector/

# 3. RoomTypeSpace ("m.space"), ParentID, and Ghost.IsBot across bridgev2 and the 5 connectors:
grep -rn "RoomTypeSpace\|ParentID\|IsBot" \
  ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/bridgev2/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/connector/
```
