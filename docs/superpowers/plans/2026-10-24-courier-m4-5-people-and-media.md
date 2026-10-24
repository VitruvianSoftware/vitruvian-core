# Courier Milestone 4.5 — People and Media Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the person using Courier everything they need to see who is in a chat, manage groups, start a new conversation or Blast (`⌘N`), combine chats with the same person across networks into one merged thread, hover a sender to see their profile or add them to macOS Contacts, and check their day in the Calendar pane — while splitting the media viewer, inline voice/video playback, stickers, link previews, and detached windows into **4.5b** so this plan stays at 14 reviewable tasks.

**Architecture:** Additive SQLite migration `8` (`profiles` contact identifiers, timezone and bot flags; `members` power levels; `room_state` full-member sync flags; `room_prefs` local name/avatar overrides; `merged_chats` and `merged_chat_rooms`), JSON-RPC protocol v6 (`room.info`, `room.refresh`, `room.setLocalOverride`, `room.setDisappearingTimer`, `room.exportText`, `room.setName`, `room.setTopic`, `room.setAvatar`, `room.inviteMembers`, `room.kickMember`, `room.setMemberAdmin`, `room.leave`, `room.delete`, `room.reportSpam`, `room.directChat`, `room.createGroup`, `people.resolve`, `people.search`, `people.contacts`, `blast.send`, `merge.create`, `merge.update`, `merge.delete`, `merge.list`, `merge.suggest`), real `bridgev2` calls through `localmatrix.MatrixConnector`, and native SwiftUI panes/sheets in `Courier` backed by `Contacts.framework` and `EventKit`.

**Tech Stack:** Go 1.26 (`maunium.net/go/mautrix` `v0.31.0`, `modernc.org/sqlite`), Swift 6 / SwiftUI (`Contacts`, `EventKit`, `DataDetection`, `SnapshotTesting`), Bazel (`//apps/desktop/courier/...`).

**Spec:** [`docs/superpowers/specs/2026-10-15-courier-iteration-1-design.md`](../specs/2026-10-15-courier-iteration-1-design.md) §4, §5, §7 (Milestone 4.5), §8 ("built for strangers") and [`docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/04-coverage-ledger.md`](../specs/2026-10-15-beeper-desktop-inventory/04-coverage-ledger.md).

---

## Summary for the Owner

### Recommended Split: 4.5a (this plan) and 4.5b (next plan)

Milestone 4.5 in the design spec and coverage ledger spans 103 ledger rows plus 7 items carried from 4.1–4.4. Putting all of them in one plan would take 23 tasks across two independent subsystems.

**Recommendation:** Split Milestone 4.5 into **4.5a (People, Groups, New Chat, Merged Chats, Contacts, and Calendar — 14 tasks, planned in full below)** and **4.5b (Media Viewer, Inline Voice & Video, Voice Notes Recording, Stickers/GIFs, Link Previews, and Detached Windows — ~9 tasks)** because people, group management, starting chats, merged chats, Contacts, and Calendar share one set of `bridgev2` APIs and SQLite tables (`profiles`, `members`, `room_state`, `merged_chats`), whereas media viewing, AVFoundation playback/recording, sticker packs, link unfurling, and multi-window coordination form an independent media and windowing pipeline.

### What 4.5a Adds

1. **Chat Info right pane (`⌘I` / `⌘⇧I`) and standalone window:** header with avatar, editable title, network badge, encryption badge, disappearing-message timer, topic/description (`ThreadDescription`), copyable phone/username/email fields (`CopyableField` / `ProfileField`), participant search, admin badges, Bookmarks tab, and plain-text chat export (`.txt`).
2. **Group management & "Edit Chat for Me":** right-click any participant to start a DM, copy their ID, promote/dismiss admin (where the bridge supports it), or remove them; add participants; edit the group's remote name, topic, and photo — or override the name and photo locally just for you ("Edit Chat for Me"); leave a group, delete a chat, or report spam.
3. **Timeline membership rows:** compact "Alice joined, Bob left" pills grouped across consecutive `m.room.member` events, gated by the `Show membership events` toggle in Settings → Chat.
4. **New Chat, New Group, and Blasts (`⌘N` / `⌘⇧N`):** account/network selector, live search across existing DMs, group-mate ghosts ("In groups", carried from 4.4), bridge contact lists, and remote phone/username lookup; multi-recipient chip bar that switches between creating a group/channel and sending an individual Blast message to each person.
5. **Merged Chats:** combine 2+ conversations with the same person across networks into one unified inbox row and timeline, with stacked network badges, a target-network switcher in the composer, and automatic merge suggestions when two DM ghosts share a phone number, email, or normalized display name.
6. **Hover cards, macOS Contacts, and Calendar pane:** hovering a sender avatar or name shows their card (`⌘⇧O` opens it from the keyboard) with one-click DM, copyable phone/email, and "Add to Contacts" / "Edit in Contacts" via macOS `Contacts.framework`; the right-rail Calendar pane shows your macOS `EventKit` day schedule alongside detected dates in messages ("Add to Calendar").
7. **Quick-reply variables carried from 4.3:** `{username}`, `{phone_number}`, and `{email}` now resolve from the ghost's synced profile identifiers.

### Surprises Found in the Pinned Bridge Code

1. **`mautrix` silently drops phone numbers and profile metadata unless two capability flags are turned on.** In `maunium.net/go/mautrix@v0.31.0/bridgev2/ghost.go:245-258`, `Ghost.UpdateInfo` calls `prepareContactInfo`, which returns `false` without saving `ghost.Identifiers` or calling `SetExtraProfileMeta` unless `MatrixConnector.GetCapabilities()` sets `ExtraProfileMeta: true`. Even with that set, lines `253-257` delete every `"tel:..."` identifier unless `ghost.Bridge.Config.PhoneNumbersInProfile` is `true`. Right now `localmatrix/connector.go:88-96` leaves both `false`, so no phone numbers, usernames, bot flags, or Slack timezones ever reach Courier's SQLite store. Task 1 turns both on and implements `SetExtraProfileMeta`.
2. **Admin promotion from Matrix (`HandleMatrixPowerLevels`) is only implemented by Signal.** In the pinned connectors, only `mautrix-signal` implements `bridgev2.PowerLevelHandlingNetworkAPI` (`handlematrix.go:561-650`, calling `ModifyMemberRoles` at power level `50`). `mautrix-whatsapp`, `mautrix-telegram`, `mautrix-gmessages`, and `mautrix-slack` do **not** implement `HandleMatrixPowerLevels` — all four read admin roles *into* Matrix during `GetChatInfo`, but cannot promote or demote admins *from* Matrix. Courier's UI must hide "Make Admin / Dismiss as Admin" on every network except Signal.
3. **Telegram does not support editing a room's topic/description from Matrix, and its phone lookup is local-only.** `mautrix-telegram` (`handlematrix.go:70-84`) implements `RoomNameHandlingNetworkAPI` and `RoomAvatarHandlingNetworkAPI`, but **not** `RoomTopicHandlingNetworkAPI`. Furthermore, `ResolveIdentifier` in `mautrix-telegram/pkg/connector/startchat.go:179-188` only looks up `+phone` numbers in the bridge's local `PhoneNumber` SQLite table — it never queries Telegram's server by phone number, and its `ResolveIdentifier` returns a `PortalKey` with `PortalInfo: nil` (`startchat.go:59-68`), so our `CreateDM` caller must fall back to `GetChatInfo` when `Chat.PortalInfo == nil`.
4. **Slack's `ResolveIdentifier` rejects email addresses despite advertising `LookupEmail: true`, and `getUserInfo` omits email/phone from `Identifiers`.** In `mautrix-slack/pkg/connector/capabilities.go:63`, the connector sets `LookupEmail: true`, but `ResolveIdentifier` (`startchat.go:48-68`) validates the string with `isValidSlackID`, which rejects `@` and `.` (`startchat.go:50`). Finding someone on Slack by name or email requires `SearchUsers` (`startchat.go:183-205`, which searches Slack's local user cache). And while `client.go:260-261` reads `Self.Profile.Email` and `Self.Profile.Phone`, `getUserInfo` (`chatinfo.go:455-469`) only writes `slack-internal:<id>` into `Identifiers` and `m.tz` into `ExtraProfile`.
5. **Google Messages implements `GetContactList` even though its capability flag says `ContactList: false`, and requires at least 2 other participants to create a group.** In `mautrix-gmessages/pkg/connector/capabilities.go:45`, `ContactList` is `false`, yet `GetContactList` is fully implemented at `startchat.go:327-346` (`Client.ListContacts` with a 5-minute cache). Meanwhile `CreateGroup` (`startchat.go:184`) returns `ErrMinimumTwoUsers` if fewer than 2 non-self participants are passed, and Google Messages has no remote group rename, topic edit, avatar edit, or member add/kick APIs in `handlematrix.go:40-46`.
6. **WhatsApp's `HandleMatrixDeleteChat` leaves a group if you are still in it.** In `mautrix-whatsapp/pkg/connector/handlematrix.go:675-685`, `HandleMatrixDeleteChat` checks if the user is joined to the group and calls `wa.Client.LeaveGroup(ctx, chatJID)` before sending `BuildDeleteChat`, whereas `HandleMatrixMembership` with `Leave` (`handlematrix.go:450-455`) calls `UpdateGroupParticipants(..., ParticipantChangeRemove)`. Our `room.leave` and `room.delete` RPCs must keep those two paths distinct and warn the user in the confirmation sheet.

### Choices for the Owner to Check

- **4.5a / 4.5b split boundary:** 4.5a ships all people, group, new-chat, Blast, merged-chat, Contacts, and Calendar features (Tasks 1–14). 4.5b (scoped below) ships the media lightbox, inline voice/video players, voice note recorder, sticker/GIF picker, link previews, and detached chat windows.
- **"Edit Chat for Me" vs "Edit Group for Everyone":** On networks where you can't edit the remote group (Google Messages, non-admin in WhatsApp/Signal/Telegram, or any 1:1 DM), clicking Edit opens the local-only override ("Edit Chat for Me", stored in `room_prefs.local_name` and `room_prefs.local_avatar_uri`). In groups where you have permission to edit the remote name/photo/topic, the sheet offers a segmented picker: **For Everyone (on network)** vs **Just for Me (on this Mac)**.
- **Merged chats are local to Courier's SQLite store:** Merging two rooms creates a row in `merged_chats` and `merged_chat_rooms` (migration 8). The underlying Matrix rooms and remote bridge portals stay untouched, so unmerging is instant and lossless.
- **Spam reporting is local-first plus bridge block/delete:** None of the five `bridgev2` connectors expose a `ReportSpam` network method. In Courier, "Report as Spam" deletes/leaves the chat via the bridge (`HandleMatrixDeleteChat` / `HandleMatrixMembership(Leave)`), marks the room hidden in `room_prefs`, and logs a local audit entry without sending telemetry anywhere.

### Main Risks the Tests Target

- **Ghost identifier & power-level persistence races:** Tested in Tasks 1 and 2 by feeding real `bridgev2.UserInfo` and `bridgev2.ChatMemberList` structs through `localmatrix.MatrixConnector` and asserting SQLite `profiles` (`identifiers_json`, `tz`, `is_bot`) and `members` (`power_level`, `membership`) rows.
- **Partial failures in `CreateGroup` and `blast.send`:** WhatsApp can create a group while failing to add individual participants (`CreateChatResponse.FailedParticipants`). Task 4 and Task 6 test partial participant failure reporting and per-room Blast failure isolation with an injected clock.
- **Merged chat timeline interleaving and pagination:** Task 7 tests cursor-based pagination (`events.listMerged`) across 3 rooms with identical and interleaved `ts_ms` values so no message is duplicated or skipped across page boundaries.
- **Capability-driven UI gating:** Tasks 9, 10, and 11 snapshot-test the Chat Info pane, participant context menu, and New Chat sheet across WhatsApp, Signal, Telegram, Google Messages, and Slack so unsupported buttons (like "Make Admin" on WhatsApp or "Edit Topic" on Telegram) never appear.

---

## Global Constraints

1. **Stay on branch `claude/courier-m4-5-plan` during planning; implementation runs in its worktree via Bazel.** All git writes, test runs, formatters, and linters go through Bazel targets (`bazel test //...`, `bazel run //tools/format`, `bazel run //tools/git:commit`, etc.).
2. **Protocol changes are additive (v5 → v6).** Update `apps/desktop/courier/protocol/protocol.json` (`"version": 6`) and `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift` (`ProtocolVersion.current = 6`) together in Task 8.
3. **Database schema change is Migration 8.** Migrations 1–7 in `apps/desktop/courier/engine/store/migrate.go` are SHA-256 hash-pinned and must not be edited. Migration 8 is added in `migrate.go` and mirrored in `schema.sql` with updated hash tests in `migrate_test.go`.
4. **No sleeps or wall-clock assertions in tests.** Use injected `clock func() time.Time` in Go and deterministic state injection in Swift tests.
5. **Views are verified with PNG snapshot tests in both light and dark appearance at real minimum widths.** No fake-network mode in the Swift app; live network verification happens on the owner's by-hand day (Task 14).
6. **Privacy ("built for strangers", Spec §8):** Never log display names, phone numbers, email addresses, usernames, or message bodies. Media and contact data never leave the Mac except to the specific remote network the user explicitly addresses.

---

## Review Focus

1. **Bridge capability accuracy:** Check the per-network table below against the pinned `go.mod` versions (`mautrix v0.31.0`, `mautrix-whatsapp v0.2609.0`, `mautrix-signal v0.2609.0`, `mautrix-telegram v0.2609.0`, `mautrix-gmessages v0.2609.0`, `mautrix-slack v0.2609.1`).
2. **Migration 8 backwards compatibility:** Every new column on existing tables (`profiles`, `members`, `room_state`, `room_prefs`) has a safe `DEFAULT` so existing 4.4 databases upgrade cleanly in place.
3. **Ledger completeness:** Every `4.5` row in `docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv` and every item carried to `4.5` in `apps/desktop/courier/docs/m4-acceptance.md` is accounted for in a 4.5a task, the 4.5b scope list, or the "Carried / not planned" table at the bottom.

---

## Per-Network Bridge Capabilities (Verified in Pinned `go.mod` Sources)

All citations below refer to the exact module versions pinned in `apps/desktop/courier/engine/go.mod`:
- `maunium.net/go/mautrix@v0.31.0`
- `go.mau.fi/mautrix-whatsapp@v0.2609.0`
- `go.mau.fi/mautrix-signal@v0.2609.0`
- `go.mau.fi/mautrix-telegram@v0.2609.0`
- `go.mau.fi/mautrix-gmessages@v0.2609.0`
- `go.mau.fi/mautrix-slack@v0.2609.1`

| Capability | WhatsApp (`v0.2609.0`) | Signal (`v0.2609.0`) | Telegram (`v0.2609.0`) | Google Messages (`v0.2609.0`) | Slack (`v0.2609.1`) |
|---|---|---|---|---|---|
| **Ghost identifiers (`UserInfo.Identifiers`)** | `tel:+<phone>` (resolves LID↔PN via `GetAltJID`); `[]` for bots (`userinfo.go:204-272`) | `tel:<E164>` when `contact.E164 != ""` (`chatinfo.go:116-118`) | `telegram:<username>` + `tel:+<phone>` when visible (`userinfo.go:238-252`) | `tel:<phone>` via `makeUserInfo` (`chatinfo.go:306-310`; `GetUserInfo` is nil no-op at `69-71`) | `slack-internal:<id>` + `ExtraProfile["m.tz"]` (`chatinfo.go:455-469`); email/phone not in `Identifiers` |
| **Member list & roles (`GetChatInfo`)** | Full list up to `MaxMemberSync`; `superAdminPL=75`, `adminPL=50`, `defaultPL=0` (`chatinfo.go:221-354`) | `Members` (`join`), `PendingMembers` (`invite`), `RequestingMembers` (`knock`), `BannedMembers` (`ban`); `moderatorPL=50` (`groupinfo.go:40-179`) | Basic chats + supergroups/channels up to `NormalizedMaxInitialSync()`; `creator=95`, `mod=40..60`, `muted=-1`; `ParticipantsHidden` flag (`chatinfo.go:38-94, 408-532`) | All participants in `wrapChatInfo`; sets `PowerLevel=50` on non-self, `0` on self, `Invite/Kick/Ban=99` (`chatinfo.go:107-155`) | Paginates `GetUsersInConversation` up to `ParticipantSyncCount`; sets `PowerLevel` on self only (`70`/`60`/`50`, `chatinfo.go:210-343`) |
| **Create group (`CreateGroup`)** | `"group"`: ≥1 participant, name ≤100, topic, avatar, disappear; returns `FailedParticipants` (`startchat.go:253-407`, `capabilities.go:28-37`) | `"group"`: ≥0 participants, name required (≤32), topic, avatar, disappear (`chatinfo.go:272-384`, `capabilities.go:230-239`) | `"group"` (`MessagesCreateChat`): 1..200 participants, name required (≤255); ignores topic/avatar/disappear at creation (`startchat.go:299-377`) | `"group"`: ≥2 participants (`ErrMinimumTwoUsers`), optional RCS name (`startchat.go:181-266`, `capabilities.go:47-53`) | `"group"` (MPIM, 2..8 users), `"public-channel"`, `"private-channel"` (name 1..80, topic, users; `startchat.go:121-181`, `capabilities.go:35-53`) |
| **Add / remove members (`HandleMatrixMembership`)** | Invite (`ParticipantChangeAdd`) & Kick/Leave (`ParticipantChangeRemove`) (`handlematrix.go:407-465`) | Invite, Kick, Leave, Ban, Unban, Accept/Reject Invite & Knock (`handlematrix.go:436-559`) | Channels/supergroups (`ChannelsInviteToChannel`, `ChannelsEditBanned`, `ChannelsLeaveChannel`) & basic groups (`MessagesAddChatUser`, `MessagesDeleteChatUser`; no kick/unban in basic groups per `capabilities.go:275`, `handlematrix.go:1355-1488`) | **Not supported** (`handlematrix.go:40-46`) | Channels only (`InviteUsersToConversationContext`, `KickUserFromConversationContext`, `LeaveConversationContext`; no-op in DM/MPIM at `handlematrix.go:285-338`) |
| **Admin promote / demote (`HandleMatrixPowerLevels`)** | **Not supported** (`handlematrix.go:33-49` does not implement `PowerLevelHandlingNetworkAPI`) | **Supported** (`ModifyMemberRoles` at `moderatorPL=50`, plus announce/attributes/member access at `handlematrix.go:561-650`) | **Not supported** (`handlematrix.go:70-84` does not implement `PowerLevelHandlingNetworkAPI`) | **Not supported** (`handlematrix.go:40-46`) | **Not supported** (`handlematrix.go:38-47`) |
| **Edit group name / avatar / topic** | Name (`467-487`), Topic (`489-509`), Avatar (`511-554`, JPEG 190..720px) in `handlematrix.go` | Name (`731-754`), Topic (`756-779`), Avatar (`781-823`) in `handlematrix.go` | Name (`1235-1284`, chats/channels/topics) & Avatar (`1286-1346`); **Topic edit not supported** (`handlematrix.go:70-84`) | **Not supported** (`handlematrix.go:40-46`) | Name (channels, `340-348`) & Topic (channels/DMs/MPIMs, `275-283`); **Avatar edit not supported** (`handlematrix.go:38-47`) |
| **Leave group / Delete chat** | Leave via `HandleMatrixMembership` (`450-455`); Delete via `HandleMatrixDeleteChat` (`670-693`, leaves group if joined + `BuildDeleteChat`) | Leave via `HandleMatrixMembership` (`480-496`); Delete via `HandleMatrixDeleteChat` (`398-434`, `DeleteForMe` sync) | Leave via `HandleMatrixMembership` (`1445-1488`); Delete via `HandleMatrixDeleteChat` (`1176-1233`, revokes DM or deletes group if `DeleteForEveryone`) | Delete only via `HandleMatrixDeleteChat` (`DeleteConversation`, `handlematrix.go:379-426`) | Leave channel via `HandleMatrixMembership` (`322-338`); **DeleteChat not supported** (`handlematrix.go:38-47`) |
| **Start DM (`ResolveIdentifier` / `CreateChatWithGhost`)** | Phone via `IsOnWhatsApp` (4h cache, rejects emails) + PN→LID (`startchat.go:84-205`) | Phone via `ContactByE164` or `LookupPhone` (`chatinfo.go:173-270`); no username lookup | `@username` / `t.me/` via `ContactsResolveUsername`, numeric ID, or `+phone` **in local bridge DB only**; returns `PortalInfo: nil` (`startchat.go:59-188`) | Any phone string (`AnyPhone: true`); calls `GetOrCreateConversation` when `createChat=true` (`startchat.go:71-174`) | Only Slack user IDs (`isValidSlackID` rejects `@`/`.`, `startchat.go:48-119`); `CreateChatWithGhost` calls `OpenConversationContext` |
| **Contact list & user search (`GetContactList` / `SearchUsers`)** | `GetContactList` (`Contacts.GetAllContacts`) & `SearchUsers` (local filter by name/phone, `startchat.go:207-251`) | `GetContactList` (`RecipientStore.LoadAllContacts`, `chatinfo.go:386-414`); no `SearchUsers` | `GetContactList` (`ContactsGetContacts`, 10m cache) & `SearchUsers` (`ContactsSearch`, `startchat.go:207-296`) | `GetContactList` implemented (`Client.ListContacts`, 5m cache, `startchat.go:327-346`) despite `ContactList: false` at `capabilities.go:45`; no `SearchUsers` | `SearchUsers` (`SearchUsersCacheContext`, `startchat.go:183-205`); no `GetContactList` |
| **Media download & voice/video limits** | Direct media (`directmedia.go:61-271`), max 2000 MiB, voice `audio/ogg; codecs=opus` (`capabilities.go:58, 95-165`) | Direct media (`directmedia.go:24-130`), max 100 MiB, voice `audio/aac` or `audio/ogg` (`capabilities.go:48, 72-143`) | Direct media (`directdownload.go:92-244`), max 2 GiB (4 GiB premium), voice `audio/ogg`/`mp3`/`mp4` + waveform (`capabilities.go:74, 99-179`, `handlematrix.go:356-363`) | Reuploaded via phone (`handlematrix.go:239-264`), max 100 MiB (`capabilities.go:67, 123-198`) | Direct media for custom emoji only (`directmedia.go:35-48`); files fetched via Slack auth URLs, max 1 GB (`capabilities.go:91, 115-175`) |
| **Calendar / Events API** | None in bridge (local macOS `EventKit` + `NSDataDetector`) | None in bridge | None in bridge | None in bridge | None in bridge |

**Unverified items:** None. Every bridge capability above was verified directly in the pinned Go module sources in `/Users/james/go/pkg/mod`.

---

## Task 1: Engine — Ghost Contact Identifiers, Timezone, and Bot Flags (Migration 8 Part 1)

**Files:**
- Modify: `apps/desktop/courier/engine/store/migrate.go`
- Modify: `apps/desktop/courier/engine/store/schema.sql`
- Modify: `apps/desktop/courier/engine/store/migrate_test.go`
- Modify: `apps/desktop/courier/engine/store/rooms.go`
- Modify: `apps/desktop/courier/engine/localmatrix/connector.go`
- Modify: `apps/desktop/courier/engine/localmatrix/intent.go`
- Modify: `apps/desktop/courier/engine/networks/host.go`
- Modify: `apps/desktop/courier/engine/localmatrix/connector_test.go`

**Interfaces:**
- SQLite Migration `8` (defined in `migrate.go` and reflected in `schema.sql` — includes all schema changes for 4.5a so migration 8 is a single atomic version bump):
  ```sql
  ALTER TABLE profiles ADD COLUMN identifiers_json TEXT NOT NULL DEFAULT '[]';
  ALTER TABLE profiles ADD COLUMN tz TEXT NOT NULL DEFAULT '';
  ALTER TABLE profiles ADD COLUMN is_bot INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE profiles ADD COLUMN remote_id TEXT NOT NULL DEFAULT '';

  ALTER TABLE members ADD COLUMN power_level INTEGER NOT NULL DEFAULT 0;

  ALTER TABLE room_state ADD COLUMN members_is_full INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE room_state ADD COLUMN total_member_count INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE room_state ADD COLUMN disappearing_type TEXT NOT NULL DEFAULT '';
  ALTER TABLE room_state ADD COLUMN disappearing_timer_ms INTEGER NOT NULL DEFAULT 0;

  ALTER TABLE room_prefs ADD COLUMN local_name TEXT NOT NULL DEFAULT '';
  ALTER TABLE room_prefs ADD COLUMN local_avatar_uri TEXT NOT NULL DEFAULT '';
  ALTER TABLE room_prefs ADD COLUMN spam_reported_ms INTEGER NOT NULL DEFAULT 0;

  CREATE TABLE merged_chats (
      merge_id    TEXT PRIMARY KEY,
      title       TEXT NOT NULL,
      avatar_uri  TEXT NOT NULL DEFAULT '',
      created_ms  INTEGER NOT NULL,
      updated_ms  INTEGER NOT NULL
  ) STRICT;

  CREATE TABLE merged_chat_rooms (
      merge_id    TEXT NOT NULL REFERENCES merged_chats(merge_id) ON DELETE CASCADE,
      room_id     TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
      position    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (merge_id, room_id)
  ) STRICT;
  CREATE INDEX idx_merged_chat_rooms_room ON merged_chat_rooms(room_id);
  ```
- `store.Profile`:
  ```go
  type Profile struct {
      UserID      string
      DisplayName string
      AvatarURI   string
      Identifiers []string // e.g. ["tel:+15550100", "telegram:alice"]
      TZ          string   // e.g. "America/Los_Angeles" from Slack m.tz
      IsBot       bool
      RemoteID    string
      UpdatedMS   int64
  }
  func (s *Store) UpsertProfileMeta(ctx context.Context, userID string, identifiers []string, tz string, isBot bool, remoteID string, updatedMS int64) error
  func (s *Store) GetProfile(ctx context.Context, userID string) (Profile, bool, error)
  ```
- `localmatrix.MatrixConnector.GetCapabilities()`:
  - Set `ExtraProfileMeta: true` in `connector.go:88-96`.
- `networks/host.go`:
  - Set `br.Config.PhoneNumbersInProfile = true` before starting connectors so `bridgev2/ghost.go:253-257` preserves `"tel:"` identifiers.
- `localmatrix.matrixIntent.SetExtraProfileMeta(ctx context.Context, data any) error`:
  - Inspect `data` (`*event.BeeperProfileExtra` or JSON-marshaled map containing `identifiers`, `remote_id`, `is_bridge_bot`, `is_network_bot`, and `"m.tz"`), extract sorted unique `identifiers []string`, `tz string`, `isBot bool`, and `remoteID string`, and call `c.store.UpsertProfileMeta`.

- [ ] **Step 1: Write failing migration and profile metadata tests**
  - In `store/migrate_test.go`, add `TestMigration8UpgradesFrom7` verifying that a v7 database migrates cleanly to v8 and preserves existing `profiles`, `members`, `room_state`, and `room_prefs` rows with their new defaults.
  - In `localmatrix/connector_test.go`, add `TestGhostUpdateInfoPersistsIdentifiersAndTZ` passing a `bridgev2.UserInfo{Identifiers: []string{"tel:+15550199", "telegram:alice"}, IsBot: ptr(true), Extra: map[string]any{"m.tz": "Europe/London"}}` through `ghost.UpdateInfo` and asserting `store.GetProfile` returns `Identifiers: ["telegram:alice", "tel:+15550199"]`, `TZ: "Europe/London"`, `IsBot: true`.
- [ ] **Step 2: Run tests to confirm they fail**
  - Run `bazel test //apps/desktop/courier/engine/store:store_test //apps/desktop/courier/engine/localmatrix:localmatrix_test` and confirm failure.
- [ ] **Step 3: Implement Migration 8, `UpsertProfileMeta`, `GetProfile`, and `SetExtraProfileMeta`**
  - Add Migration `8` to `store/migrate.go`, update `store/schema.sql`, and update the schema hash in `store/migrate_test.go`.
  - Implement `UpsertProfileMeta` and `GetProfile` in `store/rooms.go`, and populate `Profile` fields when loading DM peer profiles in `ListRooms` / `GetRoom`.
  - Set `ExtraProfileMeta: true` in `localmatrix/connector.go`, `PhoneNumbersInProfile = true` in `networks/host.go`, and implement `SetExtraProfileMeta` in `localmatrix/intent.go`.
- [ ] **Step 4: Re-run tests to confirm green**
  - Run `bazel test //apps/desktop/courier/engine/...` and verify all tests pass.

---

## Task 2: Engine — Room Power Levels, Full Member Sync, and Timeline Membership Events

**Files:**
- Modify: `apps/desktop/courier/engine/store/rooms.go`
- Modify: `apps/desktop/courier/engine/store/events.go`
- Modify: `apps/desktop/courier/engine/localmatrix/connector.go`
- Modify: `apps/desktop/courier/engine/localmatrix/intent.go`
- Modify: `apps/desktop/courier/engine/localmatrix/connector_test.go`
- Modify: `apps/desktop/courier/engine/store/store_test.go`

**Interfaces:**
- `store.Member`:
  ```go
  type Member struct {
      RoomID      string
      UserID      string
      Membership  string // "join", "invite", "leave", "ban", "knock"
      PowerLevel  int    // >= 50 is admin/moderator across WhatsApp/Signal/Telegram/Slack; >= 75 super-admin/creator
      DisplayName string
      AvatarURI   string
      Identifiers []string
      TZ          string
      IsBot       bool
      UpdatedMS   int64
  }
  func (s *Store) UpsertMemberWithRole(ctx context.Context, roomID, userID, membership string, powerLevel int, updatedMS int64) error
  func (s *Store) SetRoomMemberSyncMeta(ctx context.Context, roomID string, isFull bool, totalCount int) error
  func (s *Store) SetRoomDisappearingTimer(ctx context.Context, roomID, timerType string, timerMS int64) error
  ```
- Timeline membership events in `store.Event`:
  - When `localmatrix` receives or syncs a membership change (`m.room.member` state event or `HandleRoomMembers` diff where a user joins, is invited, leaves, or is kicked), also insert an `events` row with `type = "m.room.member"` and `content_json = {"membership": "join"|"leave"|"invite"|"ban", "target_user_id": "...", "target_name": "...", "actor_user_id": "..."}` so the timeline can group consecutive membership rows when `Show membership events` is enabled.

- [ ] **Step 1: Write failing tests for member power levels, full-sync pruning, and membership timeline events**
  - In `localmatrix/connector_test.go`, add `TestSyncChatInfoMembersAndPowerLevels` verifying:
    1. `bridgev2.ChatMemberList{IsFull: true, TotalMemberCount: 4, MemberMap: ...}` writes each member's `PowerLevel` (`75`, `50`, `0`), marks removed members as `"leave"` when `IsFull == true`, and stores `members_is_full = 1`, `total_member_count = 4`.
    2. `bridgev2.ChatInfo.Disappear` (`Type: "after_read"`, `Timer: 24 * time.Hour`) stores `disappearing_type = "after_read"` and `disappearing_timer_ms = 86400000`.
    3. A live member join/leave emits an `m.room.member` row in `events`.
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/engine/localmatrix:localmatrix_test //apps/desktop/courier/engine/store:store_test`.
- [ ] **Step 3: Implement member power-level persistence, `IsFull` reconciliation, disappearing timer state, and `m.room.member` timeline events**
  - Update `localmatrix/connector.go` (`syncChatInfo`) and `localmatrix/intent.go` (`EnsureJoined`, state event handling for `event.StateMember`, `event.StatePowerLevels`, and `event.StateBeeperDisappearingTimer`) to call `UpsertMemberWithRole`, `SetRoomMemberSyncMeta`, and `SetRoomDisappearingTimer`.
  - Update `store.ListRoomMembers` (`store/rooms.go`) to join `profiles` and return `PowerLevel`, `Identifiers`, `TZ`, and `IsBot`, ordered by `power_level DESC, display_name ASC, user_id ASC`.
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/engine/...`.

---

## Task 3: Engine — Chat Info (`room.info`), Refresh (`room.refresh`), Local Overrides ("Edit Chat for Me"), Disappearing Timer, and Text Export

**Files:**
- Create: `apps/desktop/courier/engine/actions/chatinfo.go`
- Create: `apps/desktop/courier/engine/actions/chatinfo_test.go`
- Modify: `apps/desktop/courier/engine/store/rooms.go`
- Modify: `apps/desktop/courier/engine/rpc/handlers.go`
- Modify: `apps/desktop/courier/engine/fakenet/fakenet.go`

**Interfaces:**
- `actions.RoomInfo`:
  ```go
  type RoomCapabilities struct {
      CanEditName          bool `json:"canEditName"`
      CanEditTopic         bool `json:"canEditTopic"`
      CanEditAvatar        bool `json:"canEditAvatar"`
      CanInviteMembers     bool `json:"canInviteMembers"`
      CanKickMembers       bool `json:"canKickMembers"`
      CanEditMemberAdmins  bool `json:"canEditMemberAdmins"`
      CanLeave             bool `json:"canLeave"`
      CanDelete            bool `json:"canDelete"`
      CanSetDisappearTimer bool `json:"canSetDisappearTimer"`
  }

  type RoomInfoResult struct {
      RoomID              string           `json:"roomId"`
      AccountID           string           `json:"accountId"`
      NetworkID           string           `json:"networkId"`
      PortalID            string           `json:"portalId"`
      Kind                string           `json:"kind"`
      Title               string           `json:"title"`
      RemoteTitle         string           `json:"remoteTitle"`
      LocalName           string           `json:"localName,omitempty"`
      Topic               string           `json:"topic,omitempty"`
      AvatarURI           string           `json:"avatarUri,omitempty"`
      LocalAvatarURI      string           `json:"localAvatarUri,omitempty"`
      Encrypted           bool             `json:"encrypted"`
      DisappearingType    string           `json:"disappearingType,omitempty"`
      DisappearingTimerMS int64            `json:"disappearingTimerMs,omitempty"`
      MembersIsFull       bool             `json:"membersIsFull"`
      TotalMemberCount    int              `json:"totalMemberCount"`
      Members             []MemberInfo     `json:"members"`
      Capabilities        RoomCapabilities `json:"capabilities"`
  }
  ```
- Capability computation in `actions.ComputeRoomCapabilities(networkID, kind string, selfPowerLevel int)`:
  - Uses the verified bridge matrix:
    - `CanEditMemberAdmins`: `kind == "group" && networkID == "signal" && selfPowerLevel >= 50`
    - `CanEditTopic`: `kind == "group" && (networkID == "whatsapp" || networkID == "signal" || networkID == "slack")` (plus Slack DMs/MPIMs)
    - `CanEditName`: `kind == "group" && (networkID == "whatsapp" || networkID == "signal" || networkID == "telegram" || networkID == "slack")`
    - `CanEditAvatar`: `kind == "group" && (networkID == "whatsapp" || networkID == "signal" || networkID == "telegram")`
    - `CanInviteMembers` / `CanKickMembers`: `kind == "group" && (networkID == "whatsapp" || networkID == "signal" || networkID == "telegram" || networkID == "slack")`
    - `CanLeave`: `kind == "group" && networkID != "gmessages"`
    - `CanDelete`: `networkID != "slack"`
- Actions & RPC methods:
  - `room.info` (`{roomId}`) → `RoomInfoResult`
  - `room.refresh` (`{roomId}`) → calls bridge `ChatInfoRefreshingNetworkAPI` / `GetChatInfo` + `GetUserInfo` for DM peer, updates SQLite, emits `room.updated`, returns `RoomInfoResult`
  - `room.setLocalOverride` (`{roomId, localName, localAvatarPath}`) → copies `localAvatarPath` into the local media CAS if non-empty, updates `room_prefs.local_name` and `room_prefs.local_avatar_uri` (where `store.ListRooms` prefers `COALESCE(NULLIF(rp.local_name, ''), rs.name)`), emits `room.updated`
  - `room.setDisappearingTimer` (`{roomId, timerMs}`) → dispatches `event.StateBeeperDisappearingTimer` to the bridge via `localmatrix.SendStateEvent` and updates `room_state`
  - `room.exportText` (`{roomId, destPath}`) → writes all non-redacted timeline messages in chronological order (`[2026-10-24 14:05:00] Sender: body`) to `destPath` (must be under user's home/temp directory, rejecting `..` traversal) and returns `{path, messageCount}`.

- [ ] **Step 1: Write failing tests in `actions/chatinfo_test.go`**
  - `TestRoomInfoCapabilitiesPerNetwork`: asserts `RoomCapabilities` for WhatsApp, Signal, Telegram, Google Messages, and Slack groups and DMs.
  - `TestRoomSetLocalOverrideUpdatesListRoomsTitleAndAvatar`: sets a local name and avatar on a Google Messages room, verifies `ListRooms` returns the overridden title while `RoomInfo.RemoteTitle` still shows the network title, and clears it with `""`.
  - `TestRoomExportTextWritesChronologicalTranscript`: inserts 3 messages and 1 deleted message, exports to `t.TempDir()`, and asserts the exact formatted lines.
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/engine/actions:actions_test`.
- [ ] **Step 3: Implement `actions/chatinfo.go`, store queries, and RPC handlers**
  - Implement `GetRoomInfo`, `RefreshRoom`, `SetLocalOverride`, `SetDisappearingTimer`, and `ExportRoomText` in `actions/chatinfo.go` and register RPC handlers in `rpc/handlers.go`.
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/engine/...`.

---

## Task 4: Engine — Remote Group Edits, Member Actions, Leave, Delete Chat, and Report Spam

**Files:**
- Create: `apps/desktop/courier/engine/actions/group_admin.go`
- Create: `apps/desktop/courier/engine/actions/group_admin_test.go`
- Modify: `apps/desktop/courier/engine/localmatrix/connector.go`
- Modify: `apps/desktop/courier/engine/rpc/handlers.go`
- Modify: `apps/desktop/courier/engine/fakenet/fakenet.go`

**Interfaces:**
- `localmatrix.MatrixConnector` additions:
  ```go
  func (c *MatrixConnector) SetRoomName(ctx context.Context, roomID, name string) error
  func (c *MatrixConnector) SetRoomTopic(ctx context.Context, roomID, topic string) error
  func (c *MatrixConnector) SetRoomAvatar(ctx context.Context, roomID string, data []byte, mimeType string) (string, error)
  func (c *MatrixConnector) ChangeMembership(ctx context.Context, roomID, targetUserID string, change event.Membership, reason string) error
  func (c *MatrixConnector) SetMemberPowerLevel(ctx context.Context, roomID, targetUserID string, powerLevel int) error
  func (c *MatrixConnector) DeleteChat(ctx context.Context, roomID string) error
  ```
  - Each method resolves the room's portal via `c.portalByRoomID(roomID)`, verifies the bridge connector implements the corresponding `bridgev2` interface (`RoomNameHandlingNetworkAPI`, `RoomTopicHandlingNetworkAPI`, `RoomAvatarHandlingNetworkAPI`, `MembershipHandlingNetworkAPI`, `PowerLevelHandlingNetworkAPI`, `DeleteChatHandlingNetworkAPI`), builds the `bridgev2.Matrix*` event struct with `Sender: c.UserID()`, invokes the bridge handler, and persists the updated state in `c.store`.
- RPC methods in `rpc/handlers.go`:
  - `room.setName` (`{roomId, name}`)
  - `room.setTopic` (`{roomId, topic}`)
  - `room.setAvatar` (`{roomId, filePath}`)
  - `room.inviteMembers` (`{roomId, userIds: []string}`)
  - `room.kickMember` (`{roomId, userId, reason}`)
  - `room.setMemberAdmin` (`{roomId, userId, isAdmin: bool}`) — sets power level `50` (`true`) or `0` (`false`); returns `ErrUnsupportedByNetwork` if the bridge does not implement `PowerLevelHandlingNetworkAPI`.
  - `room.leave` (`{roomId}`) — calls `ChangeMembership(ctx, roomID, selfMXID, event.MembershipLeave, "")` and hides the room from the active inbox.
  - `room.delete` (`{roomId}`) — calls `DeleteChat(ctx, roomID)` and deletes the room from `rooms` (or marks hidden if bridge delete is local-only).
  - `room.reportSpam` (`{roomId}`) — records `spam_reported_ms` in `room_prefs`, calls `DeleteChat` (or `Leave` if `DeleteChat` is unsupported on Slack), and hides the room.

- [ ] **Step 1: Write failing tests in `actions/group_admin_test.go`**
  - Extend `fakenet.FakeNetworkAPI` to implement `RoomNameHandlingNetworkAPI`, `RoomTopicHandlingNetworkAPI`, `RoomAvatarHandlingNetworkAPI`, `MembershipHandlingNetworkAPI`, `PowerLevelHandlingNetworkAPI` (configurable per network), and `DeleteChatHandlingNetworkAPI`.
  - Write tests:
    - `TestGroupSetNameTopicAndAvatar`
    - `TestGroupInviteAndKickMember`
    - `TestGroupSetMemberAdminSucceedsOnSignalAndRejectsWhatsApp`
    - `TestGroupLeaveVsDeleteChatCallsDistinctBridgeHandlers`
    - `TestReportSpamMarksRoomAndDeletesChat`
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/engine/actions:actions_test`.
- [ ] **Step 3: Implement `localmatrix` bridge dispatchers, `actions/group_admin.go`, and RPC handlers**
  - Wire all 9 RPC methods in `rpc/handlers.go` and emit `room.updated` / `inbox.changed` notifications on completion.
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/engine/...`.

---

## Task 5: Engine — Starting a DM from "In Groups", Identifier Lookup (`people.resolve`), User Search (`people.search`), and Contact Lists (`people.contacts`)

**Files:**
- Create: `apps/desktop/courier/engine/actions/people.go`
- Create: `apps/desktop/courier/engine/actions/people_test.go`
- Modify: `apps/desktop/courier/engine/localmatrix/connector.go`
- Modify: `apps/desktop/courier/engine/store/rooms.go`
- Modify: `apps/desktop/courier/engine/rpc/handlers.go`
- Modify: `apps/desktop/courier/engine/fakenet/fakenet.go`

**Interfaces:**
- `localmatrix.MatrixConnector` additions:
  ```go
  func (c *MatrixConnector) CreateDMWithGhost(ctx context.Context, loginID networkid.UserLoginID, ghostUserID string) (string, error)
  func (c *MatrixConnector) ResolveIdentifier(ctx context.Context, loginID networkid.UserLoginID, identifier string, createChat bool) (*PeopleMatch, error)
  func (c *MatrixConnector) SearchUsers(ctx context.Context, loginID networkid.UserLoginID, query string) ([]PeopleMatch, error)
  func (c *MatrixConnector) GetContactList(ctx context.Context, loginID networkid.UserLoginID) ([]PeopleMatch, error)
  ```
  - **Fix for Telegram `PortalInfo == nil` surprise:** When `ResolveIdentifier` or `CreateChatWithGhost` returns `resp.Chat` with `resp.Chat.PortalInfo == nil` (as `mautrix-telegram/pkg/connector/startchat.go:59-68` does), call `api.GetChatInfo(ctx, portal)` to populate `PortalInfo` before calling `portal.CreateMatrixRoom(ctx, api, resp.Chat.PortalInfo)`.
  - **Carried from 4.4 (`m4-acceptance.md` §4.4):** `room.directChat` (`{accountId, userId}`) opens or creates a 1:1 DM with any ghost already in `profiles` / `members` (the "In groups" section in search/New Chat) by parsing the ghost MXID (`@<network>_<remoteUserID>:courier.local`), loading or creating the `bridgev2.Ghost`, and calling `CreatingDMNetworkAPI.CreateChatWithGhost`.
- `store.SearchKnownPeople(ctx context.Context, query string, limit int) ([]KnownPerson, error)`:
  - Searches `profiles` across all rooms (joining `members` and `rooms` to know whether a 1:1 DM room already exists or the person is only seen in groups).
- RPC methods:
  - `room.directChat` (`{accountId, userId}`) → `{roomId}`
  - `people.resolve` (`{accountId, identifier, createChat: bool}`) → `{match: *PeopleMatch, roomId: string}`
  - `people.search` (`{query, accountId?: string}`) → `{existingDMs: []PeopleMatch, inGroups: []PeopleMatch, remoteResults: []PeopleMatch}`
  - `people.contacts` (`{accountId?: string}`) → `{contacts: []PeopleMatch}` (queries `ContactListingNetworkAPI.GetContactList` on each connected login that implements `bridgev2.ContactListingNetworkAPI` — note: checks the Go interface directly rather than `Cap.ContactList` so Google Messages' `GetContactList` at `startchat.go:327-346` works!).

- [ ] **Step 1: Write failing tests in `actions/people_test.go`**
  - `TestDirectChatWithGroupMateCreatesDMPortal`: seeds a group room with `@whatsapp_15550123:courier.local` (no existing DM room), calls `room.directChat`, and asserts a new `dm` room is created and returned.
  - `TestResolveIdentifierHandlesNilPortalInfoLikeTelegram`: configures `fakenet` to return `PortalInfo: nil` from `ResolveIdentifier`, and asserts `ResolveIdentifier(..., createChat: true)` falls back to `GetChatInfo` and creates the room.
  - `TestPeopleContactsCallsInterfaceEvenWhenCapabilityFlagIsFalse`: verifies Google Messages returns contacts via `ContactListingNetworkAPI`.
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/engine/actions:actions_test`.
- [ ] **Step 3: Implement `CreateDMWithGhost`, `ResolveIdentifier`, `SearchUsers`, `GetContactList`, and RPC handlers**
  - Implement in `localmatrix/connector.go`, `store/rooms.go`, `actions/people.go`, and `rpc/handlers.go`.
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/engine/...`.

---

## Task 6: Engine — Creating a Group or Channel (`room.createGroup`) and Sending a Blast (`blast.send`)

**Files:**
- Create: `apps/desktop/courier/engine/actions/create_group.go`
- Create: `apps/desktop/courier/engine/actions/blast.go`
- Create: `apps/desktop/courier/engine/actions/create_group_test.go`
- Modify: `apps/desktop/courier/engine/localmatrix/connector.go`
- Modify: `apps/desktop/courier/engine/rpc/handlers.go`
- Modify: `apps/desktop/courier/engine/fakenet/fakenet.go`

**Interfaces:**
- `room.createGroup` RPC:
  ```go
  type CreateGroupParams struct {
      AccountID    string   `json:"accountId"`
      GroupType    string   `json:"groupType"` // "group", "public-channel", "private-channel"
      Name         string   `json:"name"`
      Topic        string   `json:"topic,omitempty"`
      AvatarPath   string   `json:"avatarPath,omitempty"`
      Participants []string `json:"participants"` // ghost MXIDs or remote user IDs
  }
  type CreateGroupResult struct {
      RoomID             string   `json:"roomId"`
      FailedParticipants []string `json:"failedParticipants,omitempty"`
  }
  ```
  - Validates per-network rules from the bridge capability table before calling `GroupCreatingNetworkAPI.CreateGroup`:
    - Signal and Telegram require non-empty `Name`; Slack channels require non-empty `Name` (≤80 chars).
    - Google Messages requires `len(Participants) >= 2`.
    - Returns `FailedParticipants` from `CreateChatResponse.FailedParticipants` (`mautrix-whatsapp/pkg/connector/startchat.go:297-328`) so the UI can banner any participant who could not be added.
- `blast.send` RPC:
  ```go
  type BlastSendParams struct {
      RoomIDs        []string `json:"roomIds"` // 2..50 target DM/group room IDs
      Text           string   `json:"text"`
      AttachmentPath string   `json:"attachmentPath,omitempty"`
  }
  type BlastRoomOutcome struct {
      RoomID  string `json:"roomId"`
      EventID string `json:"eventId,omitempty"`
      Error   string `json:"error,omitempty"`
  }
  type BlastSendResult struct {
      Outcomes []BlastRoomOutcome `json:"outcomes"`
  }
  ```
  - Sends an independent message (and optional single attachment via `actions.SendMedia`) to each room in `RoomIDs`. For 1:1 DM rooms, expands `{first_name}`, `{last_name}`, `{full_name}`, `{username}`, `{phone_number}`, `{email}` per recipient using their `Profile` row before queueing in the outbox. One room's failure never aborts the remaining rooms.

- [ ] **Step 1: Write failing tests in `actions/create_group_test.go`**
  - `TestCreateGroupValidatesPerNetworkRulesAndReportsFailedParticipants`
  - `TestBlastSendExpandsRecipientVariablesAndIsolatesRoomFailures`
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/engine/actions:actions_test`.
- [ ] **Step 3: Implement `actions/create_group.go`, `actions/blast.go`, and RPC handlers**
  - Wire `room.createGroup` and `blast.send` in `rpc/handlers.go`.
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/engine/...`.

---

## Task 7: Engine — Merged Chats (`merge.*` and `events.listMerged`)

**Files:**
- Create: `apps/desktop/courier/engine/store/merged.go`
- Create: `apps/desktop/courier/engine/store/merged_test.go`
- Modify: `apps/desktop/courier/engine/rpc/handlers.go`

**Interfaces:**
- `store/merged.go`:
  ```go
  type MergedChat struct {
      MergeID    string   `json:"mergeId"`
      Title      string   `json:"title"`
      AvatarURI  string   `json:"avatarUri,omitempty"`
      RoomIDs    []string `json:"roomIds"`
      NetworkIDs []string `json:"networkIds"`
      Unread     int      `json:"unread"`
      LastTSMS   int64    `json:"lastTsMs"`
      Preview    string   `json:"preview,omitempty"`
  }

  type MergeSuggestion struct {
      Reason  string   `json:"reason"` // e.g. "tel:+15550199" or "name:alice smith"
      Title   string   `json:"title"`
      RoomIDs []string `json:"roomIds"`
  }

  func (s *Store) CreateMergedChat(ctx context.Context, title string, roomIDs []string, nowMS int64) (MergedChat, error)
  func (s *Store) UpdateMergedChat(ctx context.Context, mergeID, title string, roomIDs []string, nowMS int64) (MergedChat, error)
  func (s *Store) DeleteMergedChat(ctx context.Context, mergeID string) error
  func (s *Store) ListMergedChats(ctx context.Context) ([]MergedChat, error)
  func (s *Store) SuggestMergedChats(ctx context.Context) ([]MergeSuggestion, error)
  func (s *Store) ListMergedEvents(ctx context.Context, mergeID string, beforeTSMS int64, beforeEventID string, limit int) ([]Event, error)
  ```
- Merge rules:
  - `CreateMergedChat` and `UpdateMergedChat` require `len(roomIDs) >= 2`.
  - `SuggestMergedChats` finds unmerged 1:1 DM rooms across different networks/accounts whose peer `profiles` share either (a) a normalized `"tel:..."` or `"mailto:..."` identifier in `identifiers_json`, or (b) a normalized case-folded full display name with ≥ 2 tokens.
  - `ListMergedEvents` queries `events` where `room_id IN (SELECT room_id FROM merged_chat_rooms WHERE merge_id = ?)` ordered by `(ts_ms DESC, event_id DESC)` with keyset cursor `(beforeTSMS, beforeEventID)` so messages with identical timestamps across two rooms never skip or duplicate across pages.
- RPC methods:
  - `merge.create` (`{title, roomIds}`), `merge.update` (`{mergeId, title, roomIds}`), `merge.delete` (`{mergeId}`), `merge.list` (`{}`), `merge.suggest` (`{}`), and `events.listMerged` (`{mergeId, beforeTsMs, beforeEventId, limit}`).

- [ ] **Step 1: Write failing tests in `store/merged_test.go`**
  - `TestMergedChatCRUDAndCascadeDelete`
  - `TestSuggestMergedChatsMatchesPhoneAndMultiWordName`
  - `TestListMergedEventsKeysetPaginationWithIdenticalTimestamps`: inserts 6 events across 3 rooms (including 3 events with identical `ts_ms = 1000`) and paginates with `limit = 2`, asserting all 6 events are returned in deterministic order without duplicates.
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/engine/store:store_test`.
- [ ] **Step 3: Implement `store/merged.go` and RPC handlers in `rpc/handlers.go`**
  - Implement all 6 methods and emit `inbox.changed` on `merge.create`, `merge.update`, and `merge.delete`.
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/engine/...`.

---

## Task 8: Protocol v6, `CourierCore` Models, and Quick-Reply Variable Completion

**Files:**
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ConversationModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/InboxModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/AppModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/QuickReplies.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/SettingsModel.swift`
- Modify: `apps/desktop/courier/engine/rpc/protocol_test.go`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ProtocolContractTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/QuickRepliesTests.swift`

**Interfaces:**
- Bump `"version": 6` in `protocol/protocol.json` and `public static let current = 6` in `Protocol.swift`.
- Add Swift Codable types in `Protocol.swift`:
  - `RoomCapabilities`, `MemberInfo` (with `powerLevel`, `identifiers`, `tz`, `isBot`), `RoomInfoResult`, `PeopleMatch`, `PeopleSearchResult`, `CreateGroupParams`, `CreateGroupResult`, `BlastSendParams`, `BlastSendResult`, `MergedChat`, `MergeSuggestion`, `MembershipTimelineGroup`.
- Add `MembershipGrouper.group(events: [TimelineEvent], showMembershipEvents: Bool) -> [TimelineItem]` in `ConversationModel.swift`:
  - When `showMembershipEvents == false`, filters out `m.room.member` events.
  - When `showMembershipEvents == true`, collapses consecutive `m.room.member` events into a single `.membershipGroup(MembershipTimelineGroup)` item with summary text (e.g. `"Alice joined"`, `"Bob and 2 others joined"`, `"Carol left"`).
- Add `@Published public var showMembershipEvents: Bool` (persisted under `"courier.chat.showMembershipEvents"`, default `true`) in `SettingsModel.swift`.
- Extend `QuickReplies.RecipientContext` in `QuickReplies.swift`:
  ```swift
  public struct RecipientContext: Equatable, Sendable {
      public var fullName: String?
      public var username: String?
      public var phoneNumber: String?
      public var email: String?
  }
  ```
  - Resolves `{username}`, `{phone_number}`, and `{email}` (carried from 4.3 in `m4-acceptance.md` §4.3) by parsing the peer's `MemberInfo.identifiers` (`telegram:<username>`, `tel:<phone>`, `mailto:<email>`).

- [ ] **Step 1: Write failing protocol contract, membership grouper, and quick-reply tests**
  - Update `ProtocolContractTests.swift` and `engine/rpc/protocol_test.go` to assert version `6` and round-trip every new RPC method and payload.
  - In `QuickRepliesTests.swift`, add `testFillsUsernamePhoneAndEmailFromIdentifiers` and `testLeavesUnknownIdentifierPlaceholdersIntact`.
  - In `CourierCoreTests`, add `testMembershipGrouperCollapsesConsecutiveMemberEventsAndRespectsHideSetting`.
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/...`.
- [ ] **Step 3: Update `protocol.json`, `Protocol.swift`, `ConversationModel.swift`, `InboxModel.swift`, `AppModel.swift`, `SettingsModel.swift`, and `QuickReplies.swift`**
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/...`.

---

## Task 9: App — Chat Info Right Pane (`⌘I` / `⌘⇧I`), Standalone Window, Bookmarks Tab, Disappearing Timer, Text Export, and Timeline Membership Rows

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/ChatInfoPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/ChatInfoWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/TranscriptView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/RootSplitView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SettingsWindowView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/CourierCommands.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierSnapshotTests/SnapshotTests.swift`

**Interfaces:**
- `ChatInfoPane`:
  - Right-rail inspector (`minWidth: 280, idealWidth: 300, maxWidth: 340`) toggled by `⌘I` or `⌘⇧I`, plus `ChatInfoWindow` (`WindowGroup("Chat Info", for: String.self)`) so a chat's info can also be opened in a detached window (`ThreadInfoBrowserWindow` parity).
  - Segmented tab header: **Info** | **Bookmarks** (`BrandChatInfoPaneBookmarks`, showing pinned/bookmarked messages in the room with click-to-jump).
  - **Info tab sections:**
    1. **Header:** 64pt avatar (or stacked avatars), title (plus subtitle `"Remote name: ..."` when a local override is active), network badge (`NetworkBadge`), encryption status pill (`Encrypted` / `Not encrypted`), and action buttons (**Edit**, **Refresh**, **Export .txt**).
    2. **Topic / Description (`ThreadDescription`):** collapsible multi-line topic with clickable links.
    3. **Contact / Profile fields (`ProfileField` / `CopyableField`):** phone number (`tel:`), username (`telegram:`), email (`mailto:`), timezone (`tz` with current local time for that offset), and bot badge (`Bot`), each with one-click copy and visual `"Copied"` feedback.
    4. **Disappearing messages picker:** `Off`, `24 hours`, `7 days`, `90 days` (enabled when `capabilities.canSetDisappearTimer` is `true`).
    5. **Participants section (for groups):** member count header (`"12 members"` or `"240 members (50 synced)"` when `!membersIsFull`), filter search field (`Search participants…`), **Add People…** button (when `capabilities.canInviteMembers`), and participant rows with `Admin` / `Owner` badges.
- `MembershipGroupRow` in `TranscriptView.swift`:
  - Renders `.membershipGroup` items as a centered muted pill (`"Alice joined · 2:14 PM"`), expandable when > 2 events are collapsed.
- `SettingsWindowView.swift` (Chat tab):
  - Adds toggle `"Show membership events in timeline"` bound to `settings.showMembershipEvents`.

- [ ] **Step 1: Write failing snapshot tests in `SnapshotTests.swift`**
  - Add light and dark snapshot tests (`280x680`) for:
    - `testChatInfoPaneDMWithPhoneAndTimezone`
    - `testChatInfoPaneGroupWithAdminsAndTopic`
    - `testChatInfoPaneBookmarksTab`
    - `testTranscriptMembershipGroupRow`
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/app:CourierSnapshotTests`.
- [ ] **Step 3: Implement `ChatInfoPane.swift`, `ChatInfoWindow.swift`, `MembershipGroupRow`, Settings toggle, and `⌘I` / `⌘⇧I` menu commands**
- [ ] **Step 4: Record/verify snapshots and run all app tests**
  - Run `bazel test //apps/desktop/courier/...`.

---

## Task 10: App — Group Participant Context Menu, Edit Group / "Edit Chat for Me" Sheet, Leave, Delete, and Report Spam

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/EditGroupSheet.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/AddParticipantsSheet.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatInfoPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/InboxSidebar.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierSnapshotTests/SnapshotTests.swift`

**Interfaces:**
- `GroupParticipantRow` context menu (in `ChatInfoPane.swift`):
  - **Message `<Name>`** → calls `room.directChat` and navigates to the 1:1 DM.
  - **View Profile** → opens `UserHoverCard` popover.
  - **Copy Phone / Username / User ID** → copies identifier to `NSPasteboard`.
  - **Make Admin** / **Dismiss as Admin** → shown **only** when `roomInfo.capabilities.canEditMemberAdmins` is `true` (Signal groups where self is admin); calls `room.setMemberAdmin`.
  - **Remove from Group…** → shown when `roomInfo.capabilities.canKickMembers` is `true` and target is not self; confirms and calls `room.kickMember`.
- `EditGroupSheet` (`EditGroupModal` / `EditGroupBrowserWindow` parity):
  - Mode picker when `capabilities.canEditName || capabilities.canEditAvatar || capabilities.canEditTopic`:
    - **For Everyone (on `<Network>`)** — edits remote name (` visible` when `canEditName`), remote topic (`visible` when `canEditTopic` — hidden on Telegram!), and remote avatar (`visible` when `canEditAvatar` — hidden on Slack!).
    - **Just for Me (on this Mac)** — edits `localName` and `localAvatarPath` via `room.setLocalOverride`, with a **Reset to Network Default** button.
  - For 1:1 DMs or read-only groups (like Google Messages), opens directly in **Just for Me** mode (`Edit Chat for Me`).
- `AddParticipantsSheet`:
  - Searches `people.contacts` and `people.search`, lets the user pick 1+ people, and calls `room.inviteMembers`.
- Destructive footer actions in `ChatInfoPane` and inbox row context menu (`InboxSidebar.swift`):
  - **Leave Group…** (when `capabilities.canLeave`): confirmation alert; on WhatsApp notes that leaving notifies the group.
  - **Delete Chat…** (when `capabilities.canDelete`): confirmation alert; on WhatsApp warns that deleting an active group also leaves it (`handlematrix.go:675-685`).
  - **Report as Spam…**: confirmation alert explaining that Courier deletes/leaves the chat on the network and hides it locally.

- [ ] **Step 1: Write failing snapshot and unit tests**
  - Add light and dark snapshot tests (`480x440`) for:
    - `testEditGroupSheetSignalRemoteMode` (shows Name, Topic, Photo)
    - `testEditGroupSheetTelegramRemoteMode` (shows Name, Photo; hides Topic)
    - `testEditChatForMeSheetLocalOverrideMode`
    - `testAddParticipantsSheet`
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/app:CourierSnapshotTests`.
- [ ] **Step 3: Implement `EditGroupSheet.swift`, `AddParticipantsSheet.swift`, participant context menus, and confirmation alerts**
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/...`.

---

## Task 11: App — New Chat, New Group, and Blasts (`⌘N` / `⌘⇧N`, `StartNewChatView`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/StartNewChatView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/RootSplitView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/CourierCommands.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierSnapshotTests/SnapshotTests.swift`

**Interfaces:**
- `StartNewChatView` (triggered by `⌘N` for New Chat or `⌘⇧N` for New Group / Blast):
  - **Account / Network filter bar:** `All Networks` pill plus one pill per connected account (`NetworkBadge` + account label).
  - **Recipient chip bar (`To:`):** selected recipients appear as removable chips.
  - **Mode switcher (when ≥ 1 recipient is selected or `⌘⇧N` was pressed):**
    - **Direct Message** (when 1 recipient) → opens or creates the 1:1 DM immediately on `Return`.
    - **New Group / Channel** (when ≥ 1 recipient on WhatsApp/Signal/Telegram/Slack, or ≥ 2 on Google Messages) → shows `GroupTitleBar` + `DraftChatAvatar` picker + (on Slack) `Group DM` / `Public Channel` / `Private Channel` segmented control, and calls `room.createGroup`. Displays an inline warning banner if `CreateGroupResult.failedParticipants` is non-empty.
    - **Blast (Send Individually)** (when ≥ 2 recipients across any networks) → shows a composer bar (text + optional 1 attachment + quick-reply variable hint `{first_name}`) and calls `blast.send`, showing per-recipient delivery progress and any failed rooms.
  - **Live results list (below `To:`):**
    1. **Existing Chats** (matching DMs).
    2. **In Groups** (ghosts from shared groups via `people.search.inGroups`, opening a DM via `room.directChat` — closes the 4.4 carried item).
    3. **Contacts** (from `people.contacts` and macOS Contacts matches).
    4. **Look Up on `<Network>`** (calls `people.resolve` for a typed `+phone`, `@username`, or Slack search via `people.search.remoteResults`).

- [ ] **Step 1: Write failing snapshot tests in `SnapshotTests.swift`**
  - Add light and dark snapshot tests (`560x520`) for:
    - `testStartNewChatLookupAndInGroupsView`
    - `testStartNewGroupWithAvatarAndTitleBar`
    - `testStartNewBlastComposerView`
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/app:CourierSnapshotTests`.
- [ ] **Step 3: Implement `StartNewChatView.swift` and wire `⌘N` / `⌘⇧N` in `CourierCommands.swift` and `RootSplitView.swift`**
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/...`.

---

## Task 12: App — Merged Chats (`MergedChatEditor`, `StackedAvatars`, Unified Timeline, and Composer Network Picker)

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/MergedChatEditorSheet.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/StackedAvatarsView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/InboxSidebar.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/TranscriptView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerBar.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatInfoPane.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierSnapshotTests/SnapshotTests.swift`

**Interfaces:**
- `StackedAvatarsView`:
  - Renders overlapping avatar circles with small `NetworkBadge` icons (`MergeSuggestionNetworkIcons` / `StackedAvatars` parity) for a merged chat row in `InboxSidebar` and `ChatInfoPane`.
- `MergedChatEditorSheet` (`CreateMergedChatBrowserWindow` / `MergedChatEditor` parity):
  - Reachable from the inbox context menu (**Merge with Another Chat…**), `ChatInfoPane` (**Merge Chats…**), or a suggestion banner at the top of `ChatInfoPane` when `merge.suggest` returns a match for the current DM.
  - Lets the user edit the merged chat title, check/uncheck 2+ rooms to include, or click **Unmerge Chat** (`merge.delete`).
- Unified timeline & composer target switcher:
  - Selecting a merged chat loads `events.listMerged` into `TranscriptView`. Each message bubble displays a tiny network badge next to its timestamp so the user can see whether a message arrived on WhatsApp, Signal, or Slack.
  - `ComposerBar` shows a compact network selector menu (`Send via: WhatsApp ▾`) defaulting to the room that received the most recent message in the merged set, and dispatches `chat.send` / `chat.sendMedia` to the selected `roomId`.

- [ ] **Step 1: Write failing snapshot tests in `SnapshotTests.swift`**
  - Add light and dark snapshot tests for:
    - `testMergedChatInboxRowAndComposerTargetPicker`
    - `testMergedChatEditorSheetWithSuggestions`
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/app:CourierSnapshotTests`.
- [ ] **Step 3: Implement `StackedAvatarsView.swift`, `MergedChatEditorSheet.swift`, merged inbox rows, timeline network badges, and composer network switcher**
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/...`.

---

## Task 13: App — Hover Cards (`⌘⇧O`), macOS Contacts Integration, and the Calendar Right Pane

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/ContactsBridge.swift`
- Create: `apps/desktop/courier/app/Sources/CourierCore/CalendarBridge.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/UserHoverCard.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/CalendarPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/TranscriptView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/RootSplitView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/CourierCommands.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ContactsAndCalendarTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierSnapshotTests/SnapshotTests.swift`

**Interfaces:**
- `ContactsBridge` (`CourierCore/ContactsBridge.swift`, wrapping `Contacts.framework` behind a `ContactsStoreProtocol` for deterministic unit tests):
  ```swift
  public struct LocalContactCard: Equatable, Sendable {
      public var identifier: String
      public var givenName: String
      public var familyName: String
      public var phoneNumbers: [String]
      public var emailAddresses: [String]
  }
  public protocol ContactsStoreProtocol: Sendable {
      func authorizationStatus() -> ContactAccessState // .notDetermined, .authorized, .denied
      func requestAccess() async -> Bool
      func matchContact(identifiers: [String], displayName: String) -> LocalContactCard?
      func saveNewContact(givenName: String, familyName: String, phone: String?, email: String?) throws -> LocalContactCard
  }
  ```
- `UserHoverCard` (`BrandUserHoverCard` / `AddContactForm` / `ContactItem` / `PhoneNumber` / `Email` parity):
  - Triggered by hovering/clicking a sender avatar or name in `TranscriptView`, or pressing `⌘⇧O` (`Open User Profile`) on the focused message.
  - Shows avatar, display name, network badge, copyable phone (`tel:` link button + copy) and email (`mailto:` link button + copy), local time if `tz` is present, **Message** button (`room.directChat`), and macOS Contacts section:
    - If matched in `ContactsBridge`: shows the linked contact badge and **Open in Contacts**.
    - If not matched: inline **Add to Contacts** form (`AddContactForm`: First name, Last name, Phone, Email, **Save to macOS Contacts**).
- `CalendarBridge` (`CourierCore/CalendarBridge.swift`, wrapping `EventKit.EKEventStore` + `NSDataDetector` date extraction behind `CalendarStoreProtocol`):
  ```swift
  public struct CalendarDayEvent: Equatable, Identifiable, Sendable {
      public var id: String
      public var title: String
      public var startDate: Date
      public var endDate: Date
      public var isAllDay: Bool
      public var calendarTitle: String
      public var meetingURL: URL?
  }
  public static func detectDates(in text: String, referenceDate: Date) -> [DetectedMessageDate]
  ```
- `CalendarPane` (`CalendarPane.swift`):
  - Right-rail tab alongside Chat Info (toggled from the window toolbar or `View → Toggle Calendar Pane`, `⌘⌥K`).
  - Shows a date header (`< Today >`), permission prompt if `EventKit` access is `.notDetermined` or `.denied`, timeline of the day's events with one-click **Join Meeting** when a video call link is in the event's `url` or `notes`, and a quick **+ New Event** sheet (also opened when clicking a detected date/time inside a message bubble in `TranscriptView`).

- [ ] **Step 1: Write failing unit and snapshot tests**
  - In `ContactsAndCalendarTests.swift`:
    - `testMatchContactByNormalizedPhoneAndEmail`
    - `testSaveNewContactPersistsToMockStore`
    - `testDetectDatesExtractsTomorrowAt3PMWithInjectedReferenceDate`
  - In `SnapshotTests.swift` (light and dark):
    - `testUserHoverCardWithAddContactForm`
    - `testCalendarPaneWithDayEventsAndMeetingButton`
- [ ] **Step 2: Run tests to verify failure**
  - Run `bazel test //apps/desktop/courier/...`.
- [ ] **Step 3: Implement `ContactsBridge.swift`, `CalendarBridge.swift`, `UserHoverCard.swift`, `CalendarPane.swift`, and date links in `TranscriptView.swift`**
- [ ] **Step 4: Run tests to verify green**
  - Run `bazel test //apps/desktop/courier/...`.

---

## Task 14: Final Checks, Acceptance List Update, and the Owner's By-Hand Day

**Files:**
- Modify: `apps/desktop/courier/docs/m4-acceptance.md`

- [ ] **Step 1: Update `apps/desktop/courier/docs/m4-acceptance.md`**
  - Mark the 4.5a items carried from 4.1–4.4 as completed in 4.5a (starting a DM with someone only in a group with you; `{username}`, `{phone_number}`, `{email}` quick-reply variables; `Show membership events` setting; Chat Info pane & group management).
  - Add a `## 4.5a — People, groups, merged chats, Contacts and Calendar` section with the automated test commands and the owner's by-hand checklist below, and list the remaining `4.5b` media/windowing items under `Carried to 4.5b`.
- [ ] **Step 2: Run full automated verification suite**
  - `bazel test //apps/desktop/courier/...`
  - `bazel build --config=macos-app //apps/desktop/courier/app:Courier`
  - `bazel run //tools/format`
  - `aspect lint //apps/desktop/courier/...`
  - `bazel run //tools/secret-scan`
- [ ] **Step 3: Owner's by-hand day (live networks on the owner's Mac)**
  1. **Chat Info & identifiers (`⌘I`):** Open a 1:1 DM on WhatsApp, Signal, Telegram, Google Messages, and Slack. Press `⌘I` and confirm the peer's phone number (`tel:`), Telegram username (`telegram:`), or Slack timezone (`m.tz`) appears and copies cleanly.
  2. **Group member list & admin badges:** Open a group on each of the 5 networks, confirm the member count and admin badges match the phone/web app, and verify that **Make Admin / Dismiss as Admin** appears on Signal groups where you are an admin and is hidden on the other 4 networks.
  3. **Edit Group vs Edit Chat for Me:** Rename a test group on Signal or WhatsApp in **For Everyone** mode and confirm it updates on your phone; then set a **Just for Me** name override on a Google Messages chat and confirm it changes in Courier's sidebar without touching the phone.
  4. **Start a DM from "In groups" & New Chat (`⌘N`):** Press `⌘N`, type the name of someone who is in a group with you but has no 1:1 DM yet, click their row under **In Groups**, and verify a 1:1 DM opens. Test phone number lookup on WhatsApp/Signal and `@username` lookup on Telegram.
  5. **New Group & Blast (`⌘⇧N`):** Create a 3-person test group on WhatsApp or Signal. Then select 2 test chats in **Blast** mode, send a message containing `Hi {first_name}`, and verify each recipient gets their own personalized message.
  6. **Merged Chats:** Merge a WhatsApp DM and a Signal DM with the same person, verify their messages interleave in one timeline with per-bubble network badges, switch the composer target network between WhatsApp and Signal, send a test message on each, and then unmerge.
  7. **Hover Card, Contacts, and Calendar (`⌘⇧O`, `⌘⌥K`):** Hover a sender in a group, press `⌘⇧O`, save a test contact to macOS Contacts, and open the Calendar pane (`⌘⌥K`) to verify today's macOS Calendar events and "Add to Calendar" on a message containing a date/time.

---

## Scope of Milestone 4.5b (Next Plan — Media, Audio/Video, Stickers, Link Previews, and Detached Windows)

The following `4.5` items are deferred to **4.5b** (`2026-10-25-courier-m4-5b-media-and-windows.md`) so each plan stays under 14 tasks:

1. **Media Lightbox (`MediaLightbox` / `Lightbox` / `LightboxModal` / `ZoomPan`):** full-screen overlay for images and videos, zoom/pan, prev/next across room media, copy image (`⌘C`), save to Downloads, Quick Look (`Space`), and image rotation (carried from 4.3).
2. **Shared Media & Files tab in Chat Info (`BrandChatInfoPaneMedia`):** grid of shared photos/videos and list of shared documents/links in `ChatInfoPane`.
3. **Inline Audio & Voice Note Player (`AudioPlayer` / `AudioPlayerContext`):** waveform scrubber, `1×` / `1.5×` / `2×` playback speed, consecutive voice-note auto-advance, and `Space` to play/pause when a voice note is focused.
4. **Voice Note Recording in Composer:** microphone capture (`AVAudioRecorder` encoding OGG/Opus or M4A), live waveform, cancel/send controls, and `m.voice` MSC3245 metadata.
5. **Inline Video & GIF Playback (`VideoAttachment` / `GifAttachment`):** inline `AVPlayerView` controls, mute toggle, looping GIF/MP4 playback, and `Autoplay GIFs` setting (`Settings → Chat`).
6. **Sticker & GIF Picker (`StickerPicker`):** sticker pack grid from synced Matrix/Telegram sticker packs and recent stickers in the composer.
7. **Link Previews (`LinkPreview` / `AttachmentPreview`):** opt-in client-side OpenGraph unfurling in composer (with dismiss button) and timeline bubble cards (`Generate link previews` setting in `Settings → Chat`).
8. **vCard & Location Attachments (`ContactAttachment` / `LocationAttachment`):** rendering shared contact cards (`.vcf` → "Add to Contacts") and static map coordinate cards (opening Apple Maps on click).
9. **Detached Chat Windows (`ThreadBrowserWindow`) & Image Copy/Download Guards:** opening a conversation in its own secondary macOS window and enforcing `Disable image copy and download` (`Settings → Security`).

---

## Ledger Accounting (`ledger.tsv` Rows Tagged `4.5`)

Every row in `docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv` with `milestone = 4.5` is mapped below to its **4.5a task**, **4.5b**, or **Carried / not planned**:

| Ledger rows (`id` — `name`) | Disposition |
|---|---|
| `comp-006` (`BrandChatInfoPane`), `comp-007` (`BrandChatInfoPaneBookmarks`), `comp-100` (`ThreadDescription`), `comp-164` (`CopyableField`), `comp-203` (`ProfileField`), `win-006` (`ThreadInfoBrowserWindow`), `cmd-052` (`Toggle Chat Info`), `key-010` (`CommandOrControl+I`), `key-050` (`Meta+Shift+I`), `set-014` (`Chat details pane`), `cm-004` (`Export Messages`) | **4.5a — Task 3 & Task 9** |
| `comp-132` (`MembershipEventGroup`), `set-026` (`Show membership events`) | **4.5a — Task 2, Task 8 & Task 9** |
| `comp-066` (`EditGroupModal`), `comp-067` (`GroupParticipantItem`), `win-010` (`EditGroupBrowserWindow`), `cm-001` (`Edit Group`), `cm-002` (`Edit Chat for Me`), `cm-005` (`Delete Chat`), `cm-006` (`Leave Group`), `cm-007` (`Report as Spam`) | **4.5a — Task 4 & Task 10** |
| `comp-093` (`StartNewChatView`), `comp-094` (`GroupTitleBar`), `comp-095` (`DraftChatAvatar`), `cmd-022` (`Start New Chat`), `cmd-060` (`New Group Chat`), `key-014` (`CommandOrControl+N`), `key-042` (`Meta+N`), `key-043` (`Meta+Shift+N`) | **4.5a — Task 5, Task 6 & Task 11** |
| `comp-076` (`MergedChatEditor`), `comp-077` (`MergeSuggestionNetworkIcons`), `comp-142` (`StackedAvatars`), `win-009` (`CreateMergedChatBrowserWindow`) | **4.5a — Task 7 & Task 12** |
| `comp-013` (`BrandUserHoverCard`), `comp-037` (`AddContactForm`), `comp-038` (`ContactItem`), `comp-193` (`Email`), `comp-201` (`PhoneNumber`), `cmd-068` (`Open User Profile`), `key-057` (`Meta+Shift+O`), `ipc-007` (`contacts-get-access-status`), `ipc-008` (`contacts-request-access`), `ipc-026` (`create-contact`), `ipc-053` (`get-all-contacts`) | **4.5a — Task 1, Task 5 & Task 13** |
| `comp-032` (`CalendarPane`), `comp-033` (`CalendarGrid`), `comp-034` (`CalendarEvent`), `comp-035` (`CalendarHeader`), `comp-036` (`CalendarPermissionPrompt`), `comp-078` (`NewEventModal`), `ipc-011` (`calendar-get-access-status`), `ipc-012` (`calendar-request-access`) | **4.5a — Task 13** |
| `comp-008` (`BrandChatInfoPaneMedia`), `comp-069` (`Lightbox`), `comp-070` (`LightboxModal`), `comp-072` (`MediaLightbox`), `comp-073` (`ZoomPan`), `comp-114` (`AttachmentPreview`), `comp-116` (`AudioPlayer`), `comp-117` (`AudioPlayerContext`), `comp-118` (`ContactAttachment`), `comp-119` (`EncryptedAttachment`), `comp-121` (`FileAttachment`), `comp-122` (`GifAttachment`), `comp-124` (`ImageAttachment`), `comp-125` (`LinkPreview`), `comp-126` (`LocationAttachment`), `comp-129` (`StickerAttachment`), `comp-130` (`VideoAttachment`), `comp-145` (`StickerPicker`), `win-005` (`ThreadBrowserWindow`), `cmd-045` (`Copy Image`), `cmd-072` (`Play/Pause Voice Note`), `set-024` (`Autoplay GIFs`), `set-028` (`Generate link previews`), `set-058` (`Disable image copy and download`) | **4.5b (Media, Audio/Video, Stickers, Link Previews & Detached Windows)** |
| `comp-031` (`BatchedInviteModal`) | **Carried / not planned:** Matrix federation space-invite batching UI; Courier has no Matrix homeserver or Spaces (`04-coverage-ledger.md` marks Spaces out of scope). Group invites use `AddParticipantsSheet` (Task 10). |
| `comp-071` (`LinkwardenDialog`) | **Carried / not planned:** Third-party Linkwarden self-hosted bookmark server integration; Courier stores bookmarks locally in SQLite (`pins` / `bookmarks` in Task 9). |
| `comp-079`–`comp-087` (`AIChatSummaryDialog`, `BeeperAI*`, `MatrixRoomEncryptionStatus` cloud key backup dialog) & `comp-092` (`NewChatDialog` legacy duplicate of `StartNewChatView`) | **Carried / not planned:** Beeper Cloud AI summaries (`04-coverage-ledger.md` excludes cloud AI; local search/summarize is M5) and legacy duplicate React component (`StartNewChatView` in Task 11 is the canonical New Chat UI). |
| `comp-168` (`DesktopCapturerPicker`), `win-007` (`CallBrowserWindow`), `win-008` (`IncomingCallBrowserWindow`), `ipc-002` (`call-window-action`), `ipc-027` (`desktop-capturer-get-sources`), `ipc-059`/`ipc-060` (`incoming-call-window-*`), `ipc-089` (`open-call-window`), `ipc-103`/`ipc-104` (`pip-*`), `ipc-114` (`set-call-pip-bounds`), `ipc-121` (`set-pip-window-aspect-ratio`) | **Carried / not planned:** Live WebRTC voice/video calling and screen-sharing PiP windows. None of the five `bridgev2` connectors in `go.mod` implement live call signaling (`03-networks-backend-native.md` §1). |
| `win-002` (`MinimizeToTrayBrowserWindow`), `win-003` (`QuickSendBrowserWindow`), `win-004` (`FloatingReplyBrowserWindow`), `ipc-023` (`close-floating-window`) | **Carried to 4.6 (Polish & Power-User):** Menu-bar tray popovers, global Quick Send overlay, and floating notification reply windows belong to Milestone 4.6 ("Global shortcut and menu-bar item") per Design Spec §7. |
