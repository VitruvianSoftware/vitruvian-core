# Courier Milestone 4.5a — People, Groups, Merged Chats, Contacts, and Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Courier the people and group workflows that sit around the conversation: the Chat Info right pane (`⌘I` / `⌘⇧I`), group administration and local chat overrides (**For Everyone** vs **Just for Me**), starting new chats, groups, and Blasts (`⌘N` / `⌘⇧N`), local Merged Chats across networks, sender hover cards (`⌘⇧O`) backed by macOS `Contacts.framework`, and the Calendar right pane (`⌘⌥K`) with detected dates in messages backed by macOS `EventKit`.

**Architecture:** Courier's Go engine (`apps/desktop/courier/engine/`) embeds five `mautrix-go/bridgev2` network connectors (WhatsApp, Signal, Telegram, Google Messages, Slack) against a single local SQLite database (`courier.db`). In 4.5a, the local Matrix connector enables `bridgev2`'s `ExtraProfileMeta` and `PhoneNumbersInProfile` hooks so bridges push ghost phone numbers, usernames, timezones, and bot flags into SQLite, while new `engine/internal/actions` methods call `bridgev2`'s room-editing, membership, power-level, identifier-resolution, contact-list, group-creation, and chat-deletion interfaces and derive per-room capability flags by type-asserting each network client to those interfaces alongside the room's `m.room.power_levels`. Merged Chats are stored locally in SQLite (`merged_chats` + `merged_chat_rooms`) and interleave events across member rooms by `(ts, room_id, event_id)` while remembering which network you last replied from. On the Swift side (`apps/desktop/courier/app/`), `CourierCore` adds models for Chat Info, New Chat / Group / Blast, Merged Chats, `CNContactStore` matching, and `EKEventStore` + `NSDataDetector` date extraction, and `Courier` adds the SwiftUI views and PNG snapshot tests in light and dark mode.

**Tech Stack:** Go 1.26 (`modernc.org/sqlite`, `maunium.net/go/mautrix` v0.31.0 `bridgev2`), Swift 6 / SwiftUI on macOS 14 (`Contacts`, `EventKit`, `Foundation.NSDataDetector`), Bazel (`rules_go`, `rules_swift`, `rules_apple`).

---

## Scope & Recommended Split (4.5a vs 4.5b)

Milestone 4.5 in `docs/superpowers/specs/2026-10-15-courier-iteration-1-design.md` §7 covers two distinct subsystems across 67 inventory rows:
1. **People, groups, and sidebars (4.5a — this plan, 14 tasks):** Chat Info pane (`⌘I` / `⌘⇧I`), participants and admin actions, Edit Group (**For Everyone** vs **Just for Me**), Add Participants, Leave / Delete / Report as Spam, Export Chat, New Chat / New Group / Blasts (`⌘N` / `⌘⇧N`), contact and identifier resolution, Merged Chats, quick-reply `{recipient.*}` variables, sender hover cards (`⌘⇧O`) + macOS Contacts, and the Calendar pane (`⌘⌥K`) + detected dates in messages.
2. **Rich media playback and capture (4.5b — separate follow-up plan):** Full-window media viewer lightbox (zoom, pan, rotate, flip, frame step, multi-attachment strip, `⌘C` / `⌘S` / Quick Look), inline voice-note player (`0.5×–2×` speed, waveform scrubber, continuous playback across consecutive voice notes) and microphone voice-note recorder, inline video / GIF / sticker / audio file players, link preview cards, location map cards, shared contact cards (`.vcf`), and attachment BlurHash placeholders.

**Why split:** Combining all 67 rows into one plan would require 23 tasks spanning both `bridgev2` group/contact APIs and AVFoundation/PDFKit/QuickLook media pipelines. Splitting along the People/Sidebars vs Media boundary keeps 4.5a at 14 reviewable tasks (12 implementation + 2 verification/acceptance) and leaves 4.5b as a focused 9-task media plan.

---

## Summary for the Owner

### What 4.5a adds
- **Chat Info right pane (`⌘I`, or `⌘⇧I` to focus its search field) and standalone Chat Info window:** header with avatar, editable title, network badge, handle/phone/timezone in 1:1 chats, and member count in groups; collapsible **Shared Media**, **Files**, **Links**, **Bookmarks**, **Participants** (with search and admin badge), and **Pinned** sections; **Encryption** row (`Encrypted` vs `Transport TLS`); **Disappearing Messages** picker (reusing existing `room.setDisappearing` and `DisappearingMenu`); **Export Chat** (`.txt`); **Leave Group**, **Delete Chat**, and **Report as Spam**.
- **Group administration and local overrides:** right-clicking a participant promotes/demotes admins, removes them from the group, opens a 1:1 DM, or copies their User ID. Editing a chat's name or avatar offers **For Everyone** (pushed to the network when the bridge and your role allow it) and **Just for Me** (saved locally in `room_prefs` on every chat, even 1:1 DMs or groups where you aren't an admin).
- **Starting chats, groups, and Blasts (`⌘N` / `⌘⇧N`):** unified search across existing chats, people in your groups (`search.query`), synced bridge contacts (`people.contacts`), and phone numbers or `@usernames` (`people.resolve`). Multi-selecting recipients switches between **New Group** (names a group on one network) and **Blast** (sends a separate 1:1 message to each person across any mix of networks, and scales `{recipient.firstName}` / `{recipient.fullName}` variables in quick replies). Also resolves the item carried from 4.4 (`apps/desktop/courier/docs/m4-acceptance.md` §4.4): starting a 1:1 chat with someone not already in a group with you.
- **Merged Chats:** combine two or more chats representing the same person across networks into one unified inbox item and timeline, with a composer network pill that defaults to the network of the most recent message and switches networks on click or `⌘L`.
- **Hover cards (`⌘⇧O`) and Contacts.framework:** hovering a sender avatar/name or pressing `⌘⇧O` shows their avatar, name, network badges, identifiers, shared groups, and a **Save to Contacts** / **Edit in Contacts** button backed by macOS `Contacts.framework` (`CNContactStore`), with a clear non-blocking explanation and **Open System Settings** button if Contacts access is denied.
- **Calendar pane (`⌘⌥K`) and detected dates in messages:** a toggleable right sidebar showing your macOS Calendar agenda (`EventKit`) with 1-click **Join** buttons for video calls (`meet.google.com`, `zoom.us`, `teams.microsoft.com`, `webex.com`), plus dashed underlines on dates/times in message bubbles that open a popover to create an `EKEvent`.

### Surprises found in the pinned `bridgev2` and bridge sources
1. **Ghost phone numbers, usernames and timezones are already sent by the bridges, but Courier's local Matrix connector throws them away.** `bridgev2` only passes them on (`ghost.go:247`, mautrix v0.31.0) when the connector reports `ExtraProfileMeta: true`, and drops `tel:` numbers unless `Bridge.Config.PhoneNumbersInProfile` is true (`ghost.go:253`). Today `engine/internal/localmatrix/connector.go` leaves `ExtraProfileMeta` false and `SetExtraProfileMeta` in `intent.go` is a no-op. Task 2 turns both on and stores the metadata in `profiles`. Slack sends only its internal user ID and timezone, not email or phone.
2. **Telegram's "find by phone" only looks in the bridge's own local table, and returns no chat details.** `mautrix-telegram` `startchat.go:171` (`ResolveIdentifier`) resolves `@username` on the server, but a `+phone` only from numbers the bridge has already seen, and it never sets `PortalInfo`. Task 5 must cope with a nil `PortalInfo` from any bridge by fetching `GetChatInfo` before creating the room, with a test against a fake network that returns nil.
3. **Google Messages can create groups but can't manage them.** It has `CreateGroup` (`startchat.go:181`, which needs at least 2 other people: `ErrMinimumTwoUsers`, `:185`) and `HandleMatrixDeleteChat` (`handlematrix.go:379`), but no rename, photo, description, add/remove or admin handlers. "Just for Me" still renames a Google Messages chat on this Mac.
4. **Only Signal can change who is an admin.** `HandleMatrixPowerLevels` exists only in `mautrix-signal` (`handlematrix.go:612`). WhatsApp and Telegram show admins (they read roles in) but can't change them from here, so "Make Admin" appears on Signal only.
5. **Telegram can't edit a group's description, and Slack can't change a group photo or delete a chat.** There's no `HandleMatrixRoomTopic` in `mautrix-telegram`, and no `HandleMatrixRoomAvatar` or `HandleMatrixDeleteChat` in `mautrix-slack`. Slack membership changes only work in channels; in DMs and group DMs they are no-ops.
6. **Deleting a WhatsApp group chat also leaves the group.** `mautrix-whatsapp` `HandleMatrixDeleteChat` (`handlematrix.go:670`) leaves first if you're still a member. The Delete confirmation says so on WhatsApp.
7. **Slack finds people only by Slack user ID or by searching its cached workspace users.** `ResolveIdentifier` (`startchat.go:60`) rejects anything that isn't a Slack ID (`isValidSlackID`, `:73`), and Slack has no contact list. ⌘N on Slack therefore uses `SearchUsers` (`startchat.go:183`).

### Decisions for the owner to check
1. **4.5a / 4.5b split:** 4.5a ships all people, group, merged-chat, contacts, and calendar features (Tasks 1–14 below). 4.5b will ship the media lightbox, voice-note player/recorder, inline video/audio players, and rich attachment cards.
2. **Existing `protocol.json` methods extended rather than duplicated:**
   - `room.features` (`ChatFeatures`) is extended with 8 boolean capability fields (`can_set_name`, `can_set_topic`, `can_set_avatar`, `can_invite`, `can_kick`, `can_set_admin`, `can_leave`, `can_delete`) derived in `engine/internal/actions/features.go` by type-asserting the login's `bridgev2.NetworkAPI` client to the corresponding `bridgev2` interfaces plus the room's `m.room.power_levels` state.
   - `room.members` (`Member`) is extended with `power_level`, `is_admin`, `identifiers`, `tz`, and `is_bot`, and reused inside `room.info`.
   - `room.directChat` (`DirectChatParams`) is extended so `room_id` is optional (`string?`) and `network` (`string?`) + `account_id` (`string?`) can start a 1:1 DM with any ghost (from contacts, `ResolveIdentifier`, or `search.query`) even when you share no group room.
   - `room.setDisappearing` (`DisappearingParams`), `room.setHidden` (`RoomsFlagParams`), and `search.query` (`sections: ["bookmarks"]` with `filters: {room_ids: [room_id]}` for the Chat Info Bookmarks tab, and `sections: ["chats", "in_groups"]` for `⌘N` local search) are reused as-is.
3. **Report as Spam never leaves or deletes silently:** `room.reportSpam` (`ReportSpamParams {room_id, leave_or_delete?: bool}`) hides the chat on this Mac (`hidden = 1` in `room_prefs`) and records `spam_reported_at`. In the app, `ReportSpamSheet` has an explicit, **unticked-by-default** checkbox (`"Also leave the group"` when `canLeave` is `true`, or `"Also delete the chat"` when `canDelete` is `true`, and no checkbox when neither is supported).
4. **Contacts and Calendar permissions are strictly on-demand and local:** Courier does not touch `CNContactStore` until you open a hover card or Contacts match, and does not touch `EKEventStore` until you open the Calendar pane (`⌘⌥K`) or click a detected date. When permission is `.denied` or `.restricted`, the UI shows a non-blocking explanation with an **Open System Settings** button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts` or `Privacy_Calendars`) and never re-prompts.

### Main risks the tests target
- **Nil `PortalInfo` panic when starting a DM by phone number/username:** tested in `TestResolveIdentifierCreatesRoomWhenPortalInfoNil` (`actions_test.go`) against a fake network returning `PortalInfo: nil`.
- **Capability mismatch between UI and bridge:** tested per `bridgev2` interface in `TestFeaturesGroupAndChatCapabilitiesByInterfaceAndPowerLevel` (`features_test.go`) and against all 5 real bridge connectors in `TestGroupAndChatManagementTableMatchesTheBridges` (`networks_test.go`).
- **Silent remote side-effects on Report as Spam:** tested in `TestReportSpamHidesLocallyByDefaultAndLeavesOnlyWhenOptedIn` (`actions_test.go`) and `testReportSpamSheetDefaultsLeaveOrDeleteToFalse` (`ConversationModelTests.swift`).
- **Merged chat timeline ordering and reply-network selection:** tested in `TestMergedTimelineInterleavesAndPaginates` (`store_test.go`) and `testMergedChatComposerDefaultsToLastMessageNetworkAndSwitches` (`ConversationModelTests.swift`).
- **Denied macOS Contacts / Calendar permissions:** tested with injected `.denied` status in `ContactsBridgeTests.swift`, `CalendarBridgeTests.swift`, and light/dark PNG snapshots in `ViewSnapshotTests.swift`.

---

## Per-Network Capability Table (Verified in Pinned Bridge Sources)

Pinned in `apps/desktop/courier/engine/go.mod`: `maunium.net/go/mautrix` **v0.31.0**, `go.mau.fi/mautrix-whatsapp` **v0.2609.0**, `mautrix-signal` **v0.2609.0**, `mautrix-telegram` **v0.2609.0**, `mautrix-gmessages` **v0.2609.0**, `mautrix-slack` **v0.2609.1**. Every cell below was re-checked by grepping the method definitions in those exact module versions (paths are under `pkg/connector/`). "—" means the bridge does not define the method, so the engine's interface check gives `false`.

The engine never switches on network name: it type-asserts the login's `bridgev2.NetworkAPI` to each interface and checks my power level. This table is what a person will see as a result.

| What you can do (bridgev2 method) | WhatsApp | Signal | Telegram | Google Messages | Slack |
|---|---|---|---|---|---|
| Profile identifiers synced (`UserInfo.Identifiers`) | `tel:` phone (`userinfo.go:271`), bot flag (`:265`) | `tel:` E.164 (`chatinfo.go:117`), bot flag (`:105`) | `telegram:` username (`handletelegram.go:789`, `userinfo.go:202`) | `tel:` phone (`chatinfo.go:309`) | `slack-internal:` ID only (`chatinfo.go:465`) + `m.tz` (`:456`) |
| Rename group (`HandleMatrixRoomName`) | yes `handlematrix.go:467` | yes `handlematrix.go:398` | yes `handlematrix.go:1240` | — | yes `handlematrix.go:275` (channels) |
| Change group photo (`HandleMatrixRoomAvatar`) | yes `handlematrix.go:514` | yes `handlematrix.go:404` | yes `handlematrix.go:1288` | — | — |
| Edit description (`HandleMatrixRoomTopic`) | yes `handlematrix.go:489` | yes `handlematrix.go:430` | — | — | yes `handlematrix.go:340` |
| Add / remove people, leave (`HandleMatrixMembership`) | yes `handlematrix.go:407` | yes `handlematrix.go:436` | yes `handlematrix.go:1355` | — | yes `handlematrix.go:285` (channels only; no-op in DMs/MPIMs) |
| Make / dismiss admin (`HandleMatrixPowerLevels`) | — | yes `handlematrix.go:612` | — | — | — |
| Delete chat on the network (`HandleMatrixDeleteChat`) | yes `handlematrix.go:670` (leaves the group first if still in it) | yes `handlematrix.go:731` | yes `handlematrix.go:1176` | yes `handlematrix.go:379` | — |
| New group (`CreateGroup`) | yes `startchat.go:253` | yes `chatinfo.go:272` (name required) | yes `startchat.go:299` | yes `startchat.go:181` (needs 2+ other people) | yes `startchat.go:121` (MPIM / channels) |
| Find someone by phone / username (`ResolveIdentifier`) | yes `startchat.go:166` | yes `chatinfo.go:198` | yes `startchat.go:171` (phone only from the bridge's local table; may return `PortalInfo: nil`) | yes `startchat.go:71` | yes `startchat.go:60` (Slack user IDs only) |
| Start a DM with a known person (`CreateChatWithGhost`) | yes `startchat.go:157` | yes `chatinfo.go:173` | — (use `ResolveIdentifier` with create) | — (use `ResolveIdentifier` with create) | yes `startchat.go:99` |
| Contact list (`GetContactList`) | yes `startchat.go:192` | yes `chatinfo.go:386` | yes `startchat.go:247` | yes `startchat.go:327` (capability flag says false; method exists) | — |
| Search people on the network (`SearchUsers`) | yes `startchat.go:196` (local filter) | — | yes `startchat.go:207` | — | yes `startchat.go:183` (cached workspace users) |
| Calendar / events | none in any bridge: the Calendar pane is macOS EventKit only |

Profile metadata is delivered by `bridgev2/ghost.go` (`getExtraProfileMeta`, line 215) as `event.BeeperProfileExtra` (`event/beeper.go:154`) merged with the bridge's `ExtraProfile`. The JSON keys are `com.beeper.bridge.identifiers`, `com.beeper.bridge.remote_id`, `com.beeper.bridge.is_network_bot`, `com.beeper.bridge.is_bridge_bot`, and Slack's `m.tz`. It is only sent when the connector reports `ExtraProfileMeta: true` (`ghost.go:247`), and `tel:` identifiers are dropped unless `Bridge.Config.PhoneNumbersInProfile` is true (`ghost.go:253`).

---

## Global Constraints

1. **Bazel-only repo and toolchain operations:** Work in your assigned git worktree on the implementation branch. Run every build, test, tidy, gazelle, and git operation through its Bazel target per `AGENTS.md`: `bazel test //apps/desktop/courier/...`, `bazel run //:tidy`, `bazel run //:gazelle`, `bazel run //tools/format`, `aspect lint //apps/desktop/courier/...`, `bazel run //tools/git:commit -- --agent <you> ...`, and `bazel run //tools/git:push -- --agent <you>`. Never run raw `git commit`, `git push`, `go test`, or `swift test`.
2. **Protocol & schema versions:** Protocol bumps from `5` to `6` in `apps/desktop/courier/protocol/protocol.json`, `apps/desktop/courier/engine/internal/rpc/server.go`, and `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`. All protocol changes are additive and use `snake_case` JSON keys. Store schema bumps from `7` to `8` as a new entry in `apps/desktop/courier/engine/internal/store/migrate.go` (`schema.sql` is the version-0 baseline and is **never** edited). Migration 7's SHA-256 is pinned in `TestShippedMigrationsAreUnchanged` (`migrate_test.go`), and a 4.4 snapshot `testdata/m8.sql` is tested via `TestMigrationFromMilestone4_4` (`store_test.go`).
3. **No sleeps or wall-clock flake in tests:** Inject clocks (`store.WithNow`, `actions.WithNow`, Swift `now: () -> Date`) and synchronize on channels or synchronous fakes (`fakenet.Client`).
4. **No PII in logs, fixtures, or repo:** Use synthetic test fixtures (`Alice`, `Bob`, `+15550100101`, `@alice_test`). Never log contact names, phone numbers, email addresses, or calendar event titles.
5. **View verification:** Every new or modified SwiftUI surface in `apps/desktop/courier/app/Sources/Courier/` is verified by light and dark PNG snapshot tests in `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift` (`bazel test //apps/desktop/courier/app:CourierViewTests`). There is no fake-network mode in the macOS app binary; live network verification happens in Task 14 (James's by-hand check).

## Review Focus

- **Capability flags come from `bridgev2` interfaces + `m.room.power_levels`:** verify in Task 3 that `engine/internal/actions/features.go` never branches on `room.Network` for group/chat management flags.
- **Report as Spam safety:** verify in Tasks 3, 7, and 10 that `room.reportSpam` only hides the chat and records `spam_reported_at` unless `leave_or_delete: true` is explicitly passed, and that the UI checkbox defaults to `false`.
- **Single-chat vs Merged-chat parity:** verify in Tasks 6, 8, and 11 that opening a Merged Chat interleaves events from all member rooms and routes outgoing replies through the selected room's `room_id`.
- **On-demand macOS permissions and denied state:** verify in Tasks 12 and 13 that `CNContactStore` and `EKEventStore` are never touched at launch and render a clean denied banner with **Open System Settings** when authorization is `.denied`.

---

## Tasks

### Task 1: Store Migration 8 — Profile Metadata, Local Overrides, Spam Timestamp, and Merged Chats

**Files:**
- Modify: `apps/desktop/courier/engine/internal/store/migrate.go`
- Modify: `apps/desktop/courier/engine/internal/store/migrate_test.go`
- Create: `apps/desktop/courier/engine/internal/store/testdata/m8.sql`
- Modify: `apps/desktop/courier/engine/internal/store/store.go`
- Modify: `apps/desktop/courier/engine/internal/store/store_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/inbox.go`
- Modify: `apps/desktop/courier/engine/internal/store/inbox_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/query.go`

**Interfaces:**
- Migration 8 (`version: 8` in `migrations` slice in `migrate.go`, bumping `SchemaVersion = 8`):
  ```sql
  ALTER TABLE profiles ADD COLUMN identifiers_json TEXT NOT NULL DEFAULT '[]';
  ALTER TABLE profiles ADD COLUMN tz TEXT NOT NULL DEFAULT '';
  ALTER TABLE profiles ADD COLUMN is_bot INTEGER NOT NULL DEFAULT 0;

  ALTER TABLE room_prefs ADD COLUMN local_name TEXT NOT NULL DEFAULT '';
  ALTER TABLE room_prefs ADD COLUMN local_avatar_uri TEXT NOT NULL DEFAULT '';
  ALTER TABLE room_prefs ADD COLUMN spam_reported_at INTEGER NOT NULL DEFAULT 0;

  CREATE TABLE IF NOT EXISTS merged_chats (
      merge_id       TEXT PRIMARY KEY,
      name           TEXT NOT NULL,
      avatar_uri     TEXT NOT NULL DEFAULT '',
      last_room_id   TEXT NOT NULL DEFAULT '',
      created_ts     INTEGER NOT NULL
  ) STRICT;

  CREATE TABLE IF NOT EXISTS merged_chat_rooms (
      merge_id       TEXT NOT NULL REFERENCES merged_chats(merge_id) ON DELETE CASCADE,
      room_id        TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
      position       INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (merge_id, room_id)
  ) STRICT;
  CREATE INDEX IF NOT EXISTS idx_merged_chat_rooms_room ON merged_chat_rooms(room_id);
  ```
- In `store.go`:
  - Extend `Profile`:
    ```go
    type Profile struct {
        UserID      string
        DisplayName string
        AvatarURI   string
        UpdatedTS   int64
        Identifiers []string
        Timezone    string
        IsBot       bool
    }
    ```
  - Update `UpsertProfile(ctx context.Context, p Profile) error` so empty `Identifiers`/`Timezone` on regular Matrix profile updates do not clobber non-empty values set by `SetProfileExtraMeta`, and add:
    ```go
    func (s *Store) SetProfileExtraMeta(ctx context.Context, userID string, identifiers []string, tz string, isBot bool) error
    func (s *Store) GetProfile(ctx context.Context, userID string) (Profile, bool, error)
    func (s *Store) SetRoomLocalOverride(ctx context.Context, roomID, localName, localAvatarURI string) error
    func (s *Store) MarkRoomSpamReported(ctx context.Context, roomID string, reportedAtTS int64) error
    ```
- In `inbox.go` and `query.go`:
  - Extend `InboxRow` and `RoomSummary` with `RemoteName string`, `LocalName string`, `LocalAvatarURI string`, `SpamReportedAt int64`, and `MergeID string`.
  - In `Inbox` and `GetRoom`, compute `Name = COALESCE(NULLIF(p.local_name, ''), r.name)` and `AvatarURI = COALESCE(NULLIF(p.local_avatar_uri, ''), r.avatar_uri)` while preserving `RemoteName = r.name`.

**Steps:**
- [ ] **Step 1: Pin migration 7's hash and write failing migration 8 & override tests.**
  - In `migrate_test.go`, add migration 7's SHA-256 to `TestShippedMigrationsAreUnchanged` (so shipped migrations `1..7` are hash-pinned).
  - Create `testdata/m8.sql` capturing a v7 database (`PRAGMA user_version = 7`) with a room `!r1:courier.local`, profile `@u1:courier.local`, `room_prefs` row, and `receipts`/`deliveries`/`login_state` tables from 4.4.
  - In `store_test.go`, add `TestMigrationFromMilestone4_4` (loads `testdata/m8.sql`, opens the store, asserts `SchemaVersion == 8`, and verifies existing rows survive with default `identifiers_json = "[]"`, `local_name = ""`, `spam_reported_at = 0`) and `TestProfileExtraMetaAndLocalRoomOverrides` (asserts `SetProfileExtraMeta` round-trips `Identifiers: []string{"tel:+15550100101", "telegram:alice_test"}`, `Timezone: "America/Los_Angeles"`, `IsBot: true`, that a subsequent `UpsertProfile` with only `DisplayName: "Alice Renamed"` preserves `Identifiers`/`Timezone`/`IsBot`, and that `SetRoomLocalOverride(ctx, "!r1:courier.local", "Custom Name", "mxc://courier.local/custom")` makes `Inbox` and `GetRoom` return `Name: "Custom Name"`, `RemoteName: "Original Name"`, `LocalName: "Custom Name"`).
- [ ] **Step 2: Run the store tests and confirm they fail.**
  - Run: `bazel test //apps/desktop/courier/engine/internal/store:store_test`
  - Expected: compilation / test failure because `SchemaVersion` is still 7 and the new `Profile` fields and methods do not exist.
- [ ] **Step 3: Implement migration 8 and the `store.go` / `inbox.go` / `query.go` methods.**
  - Append migration 8 to `migrations` in `migrate.go` and bump `SchemaVersion = 8`. Do **not** edit `schema.sql`.
  - Implement `SetProfileExtraMeta`, `GetProfile`, `SetRoomLocalOverride`, `MarkRoomSpamReported`, and update `Inbox` / `GetRoom` queries.
- [ ] **Step 4: Re-run the store tests and confirm they pass.**
  - Run: `bazel test //apps/desktop/courier/engine/internal/store:store_test`
  - Expected: `PASS` (`TestShippedMigrationsAreUnchanged`, `TestMigrationFromMilestone4_4`, `TestProfileExtraMetaAndLocalRoomOverrides` all green).
- [ ] **Step 5: Commit Task 1.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add store migration 8 for profiles, overrides, and merged chats" apps/desktop/courier/engine/internal/store`

---

### Task 2: Ghost Profile Metadata & Membership Events in `localmatrix` and `host`

**Files:**
- Modify: `apps/desktop/courier/engine/internal/localmatrix/connector.go`
- Modify: `apps/desktop/courier/engine/internal/localmatrix/connector_test.go`
- Modify: `apps/desktop/courier/engine/internal/localmatrix/intent.go`
- Modify: `apps/desktop/courier/engine/internal/localmatrix/intent_test.go`
- Modify: `apps/desktop/courier/engine/internal/host/host.go`
- Modify: `apps/desktop/courier/engine/internal/host/host_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/chatstate.go`
- Modify: `apps/desktop/courier/engine/internal/store/chatstate_test.go`

**Interfaces:**
- In `localmatrix/connector.go`:
  - Set `ExtraProfileMeta: true` in `Connector.GetCapabilities()` (`connector.go:93-102`).
  - Extend `Store` interface in `connector.go`:
    ```go
    SetProfileExtraMeta(ctx context.Context, userID string, identifiers []string, tz string, isBot bool) error
    ```
  - Add `GetMembers(roomID id.RoomID) map[id.UserID]event.MemberEventContent` on `*Connector`.
- In `localmatrix/intent.go`:
  - Implement `SetExtraProfileMeta(ctx context.Context, data any) error` by decoding `data` (via JSON marshal/unmarshal into a struct with `Identifiers []string` (`json:"com.beeper.bridge.identifiers"`), `Timezone string` (`json:"m.tz"`), `IsNetworkBot bool` (`json:"com.beeper.bridge.is_network_bot"`) — the real keys of `event.BeeperProfileExtra` in mautrix v0.31.0 `event/beeper.go:154` plus Slack's `m.tz`; `data` may be a `*event.BeeperProfileExtra` or a merged `map[string]any`, and both must decode) and calling `i.conn.store.SetProfileExtraMeta(ctx, string(i.userID), meta.Identifiers, meta.Timezone, meta.IsBot)`.
  - In `InviteUser`, `EnsureJoined`, and `SendState` (when `eventType == event.StateMember`), also persist a timeline event row in `store.AppendEvent` with `Type: "m.room.member"` and JSON `content_json` (`{"membership": "join"|"invite"|"leave"|"ban", "target_user_id": ..., "displayname": ...}`) and notify `"event"` so membership changes appear in the timeline.
- In `host/host.go`:
  - Set `PhoneNumbersInProfile: true` inside `bridgeconfig.Config` when initializing each `bridgev2.Bridge`.
- In `store/chatstate.go`:
  - Extend `MemberHit` with `PowerLevel int`, `IsAdmin bool`, `Identifiers []string`, `Timezone string`, `IsBot bool`.
  - Add `RoomMembers(ctx context.Context, roomID string) ([]MemberHit, error)` joining `room_members` (`membership IN ('join', 'invite')`) with `profiles` and reading power levels from the room's `m.room.power_levels` state JSON (`users[userID]`, defaulting to `users_default`, with `IsAdmin: level >= 50`).

**Steps:**
- [ ] **Step 1: Write failing tests in `intent_test.go`, `connector_test.go`, `host_test.go`, and `chatstate_test.go`.**
  - `TestSetExtraProfileMetaPersistsIdentifiersTimezoneAndBot` (`intent_test.go`): calls `intent.SetExtraProfileMeta` twice — once with `&event.BeeperProfileExtra{Identifiers: []string{"tel:+15550100101", "telegram:alice_test"}, IsNetworkBot: true}` and once with the merged-map form `map[string]any{"com.beeper.bridge.identifiers": []any{"tel:+15550100101", "telegram:alice_test"}, "com.beeper.bridge.is_network_bot": true, "m.tz": "Europe/London"}` and asserts after each that `store.GetProfile` returns `Identifiers: []string{"tel:+15550100101", "telegram:alice_test"}` and `IsBot: true`, and after the map form also `Timezone: "Europe/London"`.
  - `TestConnectorCapabilitiesEnableExtraProfileMeta` (`connector_test.go`): asserts `conn.GetCapabilities().ExtraProfileMeta == true`.
  - `TestHostEnablesPhoneNumbersInProfile` (`host_test.go`): asserts each hosted bridge's `Config.PhoneNumbersInProfile == true`.
  - `TestRoomMembersIncludesPowerLevelsAndProfileMeta` (`chatstate_test.go`): seeds a room with `m.room.power_levels` (`{"users":{"@me:courier.local":100,"@alice:courier.local":50,"@bob:courier.local":0}}`) and profile metadata, calls `RoomMembers`, and asserts `@me:courier.local` has `PowerLevel: 100, IsAdmin: true`, `@alice:courier.local` has `PowerLevel: 50, IsAdmin: true`, and `@bob:courier.local` has `PowerLevel: 0, IsAdmin: false`.
- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `bazel test //apps/desktop/courier/engine/internal/localmatrix:localmatrix_test //apps/desktop/courier/engine/internal/host:host_test //apps/desktop/courier/engine/internal/store:store_test`
  - Expected: FAIL (`ExtraProfileMeta` is `false`, `SetExtraProfileMeta` is a no-op, `RoomMembers` does not exist).
- [ ] **Step 3: Implement the changes in `connector.go`, `intent.go`, `host.go`, and `chatstate.go`.**
- [ ] **Step 4: Re-run the tests and confirm they pass.**
  - Run: `bazel test //apps/desktop/courier/engine/internal/localmatrix:localmatrix_test //apps/desktop/courier/engine/internal/host:host_test //apps/desktop/courier/engine/internal/store:store_test`
  - Expected: `PASS`.
- [ ] **Step 5: Commit Task 2.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): capture ghost profile metadata and room member power levels" apps/desktop/courier/engine/internal/localmatrix apps/desktop/courier/engine/internal/host apps/desktop/courier/engine/internal/store`

---

### Task 3: Capability Derivation from `bridgev2` Interfaces + Power Levels, Chat Info, Local Overrides, Export, and Report as Spam

**Files:**
- Modify: `apps/desktop/courier/engine/internal/actions/features.go`
- Modify: `apps/desktop/courier/engine/internal/actions/features_test.go`
- Create: `apps/desktop/courier/engine/internal/actions/chatinfo.go`
- Modify: `apps/desktop/courier/engine/internal/actions/actions.go`
- Modify: `apps/desktop/courier/engine/internal/actions/actions_test.go`
- Modify: `apps/desktop/courier/engine/internal/fakenet/fakenet.go`
- Modify: `apps/desktop/courier/engine/internal/networks/networks_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/search.go`
- Modify: `apps/desktop/courier/engine/internal/store/search_test.go`

**Interfaces:**
- In `actions/features.go`:
  - Extend `Features` struct (`features.go:34-48`) with:
    ```go
    CanSetName   bool `json:"can_set_name"`
    CanSetTopic  bool `json:"can_set_topic"`
    CanSetAvatar bool `json:"can_set_avatar"`
    CanInvite    bool `json:"can_invite"`
    CanKick      bool `json:"can_kick"`
    CanSetAdmin  bool `json:"can_set_admin"`
    CanLeave     bool `json:"can_leave"`
    CanDelete    bool `json:"can_delete"`
    ```
  - Derive each boolean in `Features(ctx context.Context, roomID string) (Features, error)` without switching on `room.Network`:
    1. Look up the login's `bridgev2.NetworkAPI` via `a.portalAndLogin(ctx, roomID)` (if the room is not yet bound to a live login, all 8 booleans are `false`).
    2. Load the room's `*event.PowerLevelsEventContent` via `a.conn.GetPowerLevels(ctx, id.RoomID(roomID))` and compute `myLevel := pl.GetUserLevel(ids.Me)`.
    3. Compute:
       - `_, hasName := api.(bridgev2.RoomNameHandlingNetworkAPI)` → `CanSetName = !room.IsDirect && hasName && myLevel >= pl.GetEventLevel(event.StateRoomName)`
       - `_, hasTopic := api.(bridgev2.RoomTopicHandlingNetworkAPI)` → `CanSetTopic = !room.IsDirect && hasTopic && myLevel >= pl.GetEventLevel(event.StateRoomTopic)`
       - `_, hasAvatar := api.(bridgev2.RoomAvatarHandlingNetworkAPI)` → `CanSetAvatar = !room.IsDirect && hasAvatar && myLevel >= pl.GetEventLevel(event.StateRoomAvatar)`
       - `_, hasMembership := api.(bridgev2.MembershipHandlingNetworkAPI)` →
         - `CanInvite = !room.IsDirect && hasMembership && myLevel >= pl.Invite()`
         - `CanKick = !room.IsDirect && hasMembership && myLevel >= pl.Kick()`
         - `CanLeave = !room.IsDirect && hasMembership`
       - `_, hasPL := api.(bridgev2.PowerLevelHandlingNetworkAPI)` → `CanSetAdmin = !room.IsDirect && hasPL && myLevel >= pl.GetEventLevel(event.StatePowerLevels)`
       - `_, hasDelete := api.(bridgev2.DeleteChatHandlingNetworkAPI)` → `CanDelete = hasDelete`
- In `actions/chatinfo.go`:
  ```go
  type RoomLink struct {
      EventID   string `json:"event_id"`
      Sender    string `json:"sender"`
      TS        int64  `json:"ts"`
      URL       string `json:"url"`
      Host      string `json:"host"`
  }

  type RoomInfo struct {
      RoomID           string            `json:"room_id"`
      Name             string            `json:"name"`
      RemoteName       string            `json:"remote_name"`
      LocalName        string            `json:"local_name"`
      Topic            string            `json:"topic"`
      AvatarPath       string            `json:"avatar_path"`
      LocalAvatarURI   string            `json:"local_avatar_uri"`
      Network          string            `json:"network"`
      AccountID        string            `json:"account_id"`
      IsDirect         bool              `json:"is_direct"`
      Encrypted        bool              `json:"encrypted"`
      DisappearingMs   int64             `json:"disappearing_ms"`
      PinnedEventIDs   []string          `json:"pinned_event_ids"`
      Members          []store.MemberHit `json:"members"`
      SharedMedia      []store.Event     `json:"shared_media"`
      SharedFiles      []store.Event     `json:"shared_files"`
      SharedLinks      []RoomLink        `json:"shared_links"`
      Features         Features          `json:"features"`
  }

  func (a *Actions) RoomInfo(ctx context.Context, roomID string, refresh bool) (RoomInfo, error)
  func (a *Actions) SetRoomLocalOverride(ctx context.Context, roomID, localName, localAvatarPath string) error
  func (a *Actions) ExportChat(ctx context.Context, roomID, destPath string) (int, error)
  func (a *Actions) ReportSpam(ctx context.Context, roomID string, leaveOrDelete bool) error
  ```
  - When `refresh == true` in `RoomInfo`, fetch `client.GetChatInfo(ctx, portal)` and apply `portal.UpdateBridgeInfo(ctx)` before reading SQLite.
  - `ReportSpam(ctx, roomID, leaveOrDelete)` **always** sets `s.SetHidden(ctx, []string{roomID}, true)` and `s.MarkRoomSpamReported(ctx, roomID, a.now().UnixMilli())`. Only when `leaveOrDelete == true` does it check `Features(ctx, roomID)` and call `LeaveRoom(ctx, roomID)` (if `!room.IsDirect && feat.CanLeave`) or `DeleteChat(ctx, roomID)` (if `feat.CanDelete`).

**Steps:**
- [ ] **Step 1: Write failing tests in `features_test.go`, `networks_test.go`, `actions_test.go`, and `search_test.go`.**
  - `TestFeaturesGroupAndChatCapabilitiesByInterfaceAndPowerLevel` (`features_test.go`): table test with 6 subcases where a fake `bridgev2.NetworkAPI` omits one interface at a time (`RoomNameHandlingNetworkAPI`, `RoomTopicHandlingNetworkAPI`, `RoomAvatarHandlingNetworkAPI`, `MembershipHandlingNetworkAPI`, `PowerLevelHandlingNetworkAPI`, `DeleteChatHandlingNetworkAPI`) and asserts the corresponding `Can*` boolean flips from `true` to `false`, plus a subcase where `myLevel = 0` and required level is `50` asserting `CanSetName`, `CanSetTopic`, `CanSetAvatar`, `CanInvite`, `CanKick`, and `CanSetAdmin` are `false` while `CanLeave` remains `true`, and a 1:1 DM subcase (`IsDirect: true`) asserting all group booleans are `false` while `CanDelete` remains `true` when `DeleteChatHandlingNetworkAPI` is implemented.
  - `TestGroupAndChatManagementTableMatchesTheBridges` (`networks_test.go`): inspects the 5 real bridge `NetworkAPI` types in `apps/desktop/courier/engine/internal/networks` and asserts their interface satisfaction matches the Per-Network Capability Table (`whatsapp`: name/topic/avatar/membership/delete=`true`, powerlevels=`false`; `signal`: all 6=`true`; `telegram`: name/avatar/membership/delete=`true`, topic/powerlevels=`false`; `gmessages`: delete=`true`, the other 5=`false`; `slack`: name/topic/membership=`true`, avatar/powerlevels/delete=`false`).
  - `TestRoomInfoAndSetLocalOverride` (`actions_test.go`): seeds a group room with 2 members, 1 image event, 1 file event, and 1 text event containing `https://example.com/spec`, calls `RoomInfo`, and asserts ` len(info.Members) == 2`, `len(info.SharedMedia) == 1`, `len(info.SharedFiles) == 1`, `info.SharedLinks[0].URL == "https://example.com/spec"`, `info.SharedLinks[0].Host == "example.com"`; then calls `SetRoomLocalOverride(ctx, roomID, "Renamed Locally", "")` and asserts `info.Name == "Renamed Locally"` and `info.RemoteName == "Original Group"`.
  - `TestExportChatWritesChronologicalPlainText` (`actions_test.go`): seeds 2 messages at `ts = 1700000000000` (`Alice`: `"Hello"`) and `ts = 1700000060000` (`Bob`: `"World"`), calls `ExportChat(ctx, roomID, tmpFile)`, and asserts `count == 2` and file contents equal `"[2023-11-14 22:13:20 UTC] Alice: Hello\n[2023-11-14 22:14:20 UTC] Bob: World\n"`.
  - `TestReportSpamHidesLocallyByDefaultAndLeavesOnlyWhenOptedIn` (`actions_test.go`): calls `ReportSpam(ctx, roomID, false)` on a group room and asserts `room.Hidden == true`, `room.SpamReportedAt == 1700000000000`, and `len(fakenet.Calls()) == 0`; then calls `ReportSpam(ctx, roomID, true)` and asserts `fakenet.Calls()` records a `HandleMatrixMembership` leave call.
- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `bazel test //apps/desktop/courier/engine/internal/actions:actions_test //apps/desktop/courier/engine/internal/networks:networks_test //apps/desktop/courier/engine/internal/store:store_test`
  - Expected: FAIL.
- [ ] **Step 3: Implement `features.go`, `chatinfo.go`, `fakenet.go` hooks, and link/attachment helpers in `search.go`.**
- [ ] **Step 4: Re-run the tests and confirm they pass.**
  - Run: `bazel test //apps/desktop/courier/engine/internal/actions:actions_test //apps/desktop/courier/engine/internal/networks:networks_test //apps/desktop/courier/engine/internal/store:store_test`
  - Expected: `PASS`.
- [ ] **Step 5: Commit Task 3.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): derive group capabilities from bridgev2 interfaces and add chat info actions" apps/desktop/courier/engine/internal/actions apps/desktop/courier/engine/internal/fakenet apps/desktop/courier/engine/internal/networks apps/desktop/courier/engine/internal/store`

---

### Task 4: Remote Group Management Actions (Name, Topic, Avatar, Invite, Kick, Admin, Leave, Delete)

**Files:**
- Create: `apps/desktop/courier/engine/internal/actions/group.go`
- Modify: `apps/desktop/courier/engine/internal/actions/actions_test.go`
- Modify: `apps/desktop/courier/engine/internal/fakenet/fakenet.go`

**Interfaces:**
- In `actions/group.go`:
  ```go
  func (a *Actions) SetRoomName(ctx context.Context, roomID, name string) error
  func (a *Actions) SetRoomTopic(ctx context.Context, roomID, topic string) error
  func (a *Actions) SetRoomAvatar(ctx context.Context, roomID, filePath string) error
  func (a *Actions) InviteMembers(ctx context.Context, roomID string, userIDs []string) error
  func (a *Actions) KickMember(ctx context.Context, roomID, userID, reason string) error
  func (a *Actions) SetMemberAdmin(ctx context.Context, roomID, userID string, isAdmin bool) error
  func (a *Actions) LeaveRoom(ctx context.Context, roomID string) error
  func (a *Actions) DeleteChat(ctx context.Context, roomID string) error
  ```
- Each method checks the corresponding `Features` capability flag first (returning `ErrUnsupported` if the bridge or the user's power level does not allow it), constructs the `event.Event` with `Sender: ids.Me` and `RoomID: id.RoomID(roomID)`, and dispatches it through `portal.ReceiveMatrixEvent(ctx, evt)` (for state events `m.room.name`, `m.room.topic`, `m.room.avatar`, `m.room.member`, `m.room.power_levels`) or `portal.HandleMatrixDeleteChat` / `api.(bridgev2.DeleteChatHandlingNetworkAPI).HandleMatrixDeleteChat` for `DeleteChat`.
- When `LeaveRoom` or `DeleteChat` succeeds on the bridge, update local SQLite (`SetHidden(ctx, []string{roomID}, true)` and update `@me:courier.local`'s membership in `room_members` to `'leave'`) and emit `Changed{Kind: "room", RoomIDs: []string{roomID}}`.

**Steps:**
- [ ] **Step 1: Write failing tests in `actions_test.go`.**
  - `TestGroupSetNameTopicAvatarUpdatesStoreAndCallsBridge`: calls `SetRoomName(ctx, roomID, "Weekend Hike")`, `SetRoomTopic(ctx, roomID, "Pack water")`, and `SetRoomAvatar(ctx, roomID, pngPath)` and asserts `fakenet` recorded `HandleMatrixRoomName("Weekend Hike")`, `HandleMatrixRoomTopic("Pack water")`, and `HandleMatrixRoomAvatar`, and SQLite `GetRoom` reflects the updated name, topic, and avatar URI.
  - `TestGroupInviteKickAndSetAdmin`: calls `InviteMembers(ctx, roomID, []string{"@carol:courier.local"})`, `SetMemberAdmin(ctx, roomID, "@carol:courier.local", true)`, and `KickMember(ctx, roomID, "@carol:courier.local", "wrong group")`, asserting `fakenet` recorded invite, power-level 50, and leave membership transitions, and `RoomMembers` reflects each transition.
  - `TestGroupLeaveAndDeleteChat`: calls `LeaveRoom(ctx, roomID)` and `DeleteChat(ctx, roomID)` and asserts `fakenet` recorded both calls and the room is marked hidden in SQLite.
  - `TestGroupActionsRejectWhenCapabilityFalse`: demotes `@me:courier.local` to power level `0` and asserts `SetRoomName`, `InviteMembers`, `KickMember`, and `SetMemberAdmin` all return `ErrUnsupported` without calling `fakenet`.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/actions:actions_test` and confirm failure.**
- [ ] **Step 3: Implement `actions/group.go` and extend `fakenet/fakenet.go` to record name, topic, avatar, membership, power-level, and delete-chat calls.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/engine/internal/actions:actions_test` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 4.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add remote group management actions" apps/desktop/courier/engine/internal/actions apps/desktop/courier/engine/internal/fakenet`

---

### Task 5: Starting Chats (Including Without a Shared Group), Contact Lists, Identifier Resolution, New Group, and Blasts

**Files:**
- Modify: `apps/desktop/courier/engine/internal/actions/privacy.go`
- Modify: `apps/desktop/courier/engine/internal/actions/privacy_test.go`
- Create: `apps/desktop/courier/engine/internal/actions/startchat.go`
- Modify: `apps/desktop/courier/engine/internal/actions/actions_test.go`
- Modify: `apps/desktop/courier/engine/internal/fakenet/fakenet.go`

**Interfaces:**
- In `actions/privacy.go`:
  - Extend `DirectChat` (currently `DirectChat(ctx context.Context, viaRoomID, userID string) (string, error)` at `privacy.go:195`) with:
    ```go
    func (a *Actions) DirectChatWithAccount(ctx context.Context, viaRoomID, network, accountID, userID string) (string, error)
    ```
    When `viaRoomID != ""`, it resolves the login from `viaRoomID` as in 4.4. When `viaRoomID == ""`, it resolves the login from `(network, accountID)` (or the sole connected login for `network` if `accountID == ""`) and creates or reuses the 1:1 DM room with `userID` via `CreateChatWithGhostHandlingNetworkAPI.CreateChatWithGhost`. Telegram and Google Messages don't implement `CreateChatWithGhost`: there, fall back to `ResolveIdentifier(ctx, <the ghost's first identifier, e.g. its tel: or telegram: value>, createChat=true)`, and if the ghost has no usable identifier return `ErrUnsupported` (the app then hides **Message** for that person). Test: `TestDirectChatFallsBackToResolveIdentifierWithoutCreateChatWithGhost` with a fake network lacking the interface, asserting the fallback call carries `"telegram:alice_test"`. This closes the 4.4 carried item ("Starting a chat with someone who is not in a group with you").
- In `actions/startchat.go`:
  ```go
  type ContactCandidate struct {
      UserID      string   `json:"user_id"`
      Name        string   `json:"name"`
      AvatarPath  string   `json:"avatar_path"`
      Network     string   `json:"network"`
      AccountID   string   `json:"account_id"`
      Identifiers []string `json:"identifiers"`
      RoomID      string   `json:"room_id,omitempty"`
  }

  func (a *Actions) ListContacts(ctx context.Context, network, accountID, query string) ([]ContactCandidate, error)
  func (a *Actions) ResolveIdentifier(ctx context.Context, network, accountID, identifier string, startChat bool) (ContactCandidate, error)
  func (a *Actions) CreateGroup(ctx context.Context, network, accountID, name string, userIDs []string) (string, error)
  func (a *Actions) SendBlast(ctx context.Context, roomIDs []string, text string) ([]store.Event, error)
  ```
  - **Critical `PortalInfo == nil` guard in `ResolveIdentifier` and `DirectChatWithAccount`:** When `ResolveIdentifier(..., startChat=true)` or `CreateChatWithGhost` returns a `*bridgev2.CreateChatResponse` whose `PortalInfo == nil` (Telegram's `ResolveIdentifier` does; treat it as possible from any bridge), call `client.GetChatInfo(ctx, resp.Portal)` to populate `PortalInfo` before calling `resp.Portal.CreateMatrixRoom(ctx, login, info)`.

**Steps:**
- [ ] **Step 1: Write failing tests in `privacy_test.go` and `actions_test.go`.**
  - `TestDirectChatWithoutSharedGroupRoom` (`privacy_test.go`): calls `DirectChatWithAccount(ctx, "", "signal", "acc-sig", "@ghost:courier.local")` when no shared group exists and asserts it creates and returns `"!dm-ghost:courier.local"` with `IsDirect == true`.
  - `TestResolveIdentifierCreatesRoomWhenPortalInfoNil` (`actions_test.go`): configures `fakenet` to return `PortalInfo: nil` from `ResolveIdentifier` (as Telegram's `ResolveIdentifier` does) and `ChatInfo{Name: ptr("Alice")}` from `GetChatInfo`, calls `ResolveIdentifier(ctx, "whatsapp", "", "+15550100101", true)`, and asserts `cand.RoomID != ""`, `cand.Name == "Alice"`, and SQLite has the created 1:1 room with `Alice` joined.
  - `TestListContactsMergesContactListAndUserSearch` (`actions_test.go`): configures `fakenet` with 2 contacts from `GetContactList` and 1 hit from `SearchUsers`, calls `ListContacts(ctx, "whatsapp", "", "ali")`, and asserts the filtered candidate list returns `Alice` with her avatar path and `tel:+15550100101` identifier.
  - `TestCreateGroupAndSendBlast` (`actions_test.go`): calls `CreateGroup(ctx, "whatsapp", "", "Trip Planners", []string{"@u1:courier.local", "@u2:courier.local"})` and asserts a new group room is created in SQLite; then calls `SendBlast(ctx, []string{dmRoom1, dmRoom2}, "Hey team")` and asserts 2 independent `m.room.message` events are stored and dispatched to `dmRoom1` and `dmRoom2`.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/actions:actions_test` and confirm failure.**
- [ ] **Step 3: Implement `DirectChatWithAccount` in `privacy.go`, `startchat.go`, and `fakenet` support for `ResolveIdentifier`, `GetContactList`, `SearchUsers`, and `CreateGroup`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/engine/internal/actions:actions_test` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 5.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add identifier resolution, contact sync, group creation, and blasts" apps/desktop/courier/engine/internal/actions apps/desktop/courier/engine/internal/fakenet`

---

### Task 6: Merged Chats in the Store and Actions

**Files:**
- Create: `apps/desktop/courier/engine/internal/store/merged.go`
- Modify: `apps/desktop/courier/engine/internal/store/store_test.go`
- Modify: `apps/desktop/courier/engine/internal/actions/actions.go`
- Modify: `apps/desktop/courier/engine/internal/actions/actions_test.go`

**Interfaces:**
- In `store/merged.go`:
  ```go
  type MergedChat struct {
      MergeID    string   `json:"merge_id"`
      Name       string   `json:"name"`
      AvatarURI  string   `json:"avatar_uri"`
      LastRoomID string   `json:"last_room_id"`
      RoomIDs    []string `json:"room_ids"`
      Networks   []string `json:"networks"`
      CreatedTS  int64    `json:"created_ts"`
  }

  type MergeSuggestion struct {
      DisplayName string   `json:"display_name"`
      Reason      string   `json:"reason"` // "identifier" or "display_name"
      RoomIDs     []string `json:"room_ids"`
      Networks    []string `json:"networks"`
  }

  func (s *Store) CreateMergedChat(ctx context.Context, name string, roomIDs []string) (MergedChat, error)
  func (s *Store) UpdateMergedChat(ctx context.Context, mergeID, name string, roomIDs []string, lastRoomID string) (MergedChat, error)
  func (s *Store) DeleteMergedChat(ctx context.Context, mergeID string) error
  func (s *Store) ListMergedChats(ctx context.Context) ([]MergedChat, error)
  func (s *Store) SuggestMergedChats(ctx context.Context) ([]MergeSuggestion, error)
  func (s *Store) MergedEventsBefore(ctx context.Context, mergeID string, before *Cursor, limit int) ([]Event, bool, error)
  func (s *Store) MergedEventsAfter(ctx context.Context, mergeID string, after *Cursor, limit int) ([]Event, bool, error)
  func (s *Store) MergedEventsAround(ctx context.Context, mergeID, roomID, eventID string, limit int) ([]Event, bool, bool, error)
  ```
- `CreateMergedChat` requires `len(roomIDs) >= 2`, assigns `merge_id = "merge:" + uuid`, sets `last_room_id` to the member room with the highest `last_ts`, and inserts rows in `merged_chats` and `merged_chat_rooms`.
- `SuggestMergedChats` finds unmerged 1:1 DM rooms across different networks whose other participant shares a normalized phone/email identifier in `profiles.identifiers_json` (`reason: "identifier"`) or an exact case-insensitive non-empty `display_name` (`reason: "display_name"`).
- When `AppendEvent` stores a message in a room belonging to a `merged_chat_rooms` entry, it updates `merged_chats.last_room_id = roomID` so the merged composer automatically targets the network of the latest message.

**Steps:**
- [ ] **Step 1: Write failing tests in `store_test.go`.**
  - `TestMergedChatCRUDAndLastRoomTracking`: creates a merged chat across `!wa:courier.local` (`whatsapp`, `last_ts = 100`) and `!sig:courier.local` (`signal`, `last_ts = 200`), asserts `mc.LastRoomID == "!sig:courier.local"`, appends a new message at `ts = 300` in `!wa:courier.local`, and asserts `ListMergedChats` now reports `LastRoomID == "!wa:courier.local"`; then deletes the merge and asserts both rooms remain intact with `MergeID == ""`.
  - `TestMergedTimelineInterleavesAndPaginates`: seeds 3 events in `!wa:courier.local` (`ts = 10, 30, 50`) and 3 events in `!sig:courier.local` (`ts = 20, 40, 60`), paginates with `MergedEventsBefore` (`limit = 4`), and asserts the returned event timestamps are `[30, 40, 50, 60]` with `hasMore == true`, and the next page returns `[10, 20]` with `hasMore == false`.
  - `TestSuggestMergedChatsMatchesByPhoneAndName`: seeds 2 1:1 rooms on `whatsapp` and `signal` whose ghosts share `"tel:+15550100101"` and 2 1:1 rooms on `telegram` and `slack` whose ghosts share `DisplayName: "Bob Carter"`, and asserts `SuggestMergedChats` returns both pairs with `Reason: "identifier"` first and `Reason: "display_name"` second.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/store:store_test` and confirm failure.**
- [ ] **Step 3: Implement `store/merged.go` and hook `last_room_id` updates into `AppendEvent` in `store.go`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/engine/internal/store:store_test` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 6.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add merged chats storage, suggestions, and interleaved pagination" apps/desktop/courier/engine/internal/store apps/desktop/courier/engine/internal/actions`

---

### Task 7: Protocol 6 Schema & RPC Handlers

**Files:**
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Create: `apps/desktop/courier/protocol/examples/room-info.json`
- Create: `apps/desktop/courier/protocol/examples/people-resolve.json`
- Create: `apps/desktop/courier/protocol/examples/merge-create.json`
- Modify: `apps/desktop/courier/engine/internal/rpc/server.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/methods.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/messages.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/messages_test.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/organise.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/organise_test.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/presence.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/presence_test.go`
- Create: `apps/desktop/courier/engine/internal/rpc/people.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/conformance_test.go`

**Interfaces:**
- Bump `"protocol": 6` in `apps/desktop/courier/protocol/protocol.json` and `ProtocolVersion = 6` in `engine/internal/rpc/server.go`.
- **Existing types and methods extended in `protocol.json`:**
  - `ChatFeatures`: add `can_set_name: bool`, `can_set_topic: bool`, `can_set_avatar: bool`, `can_invite: bool`, `can_kick: bool`, `can_set_admin: bool`, `can_leave: bool`, `can_delete: bool`.
  - `Member`: add `power_level: int`, `is_admin: bool`, `identifiers: string[]`, `tz: string`, `is_bot: bool`.
  - `DirectChatParams` (`room.directChat`): change `room_id` to `"string?"` and add `network: "string?"`, `account_id: "string?"`.
  - `InboxRow`: add `remote_name: string`, `local_name: string`, `local_avatar_path: string`, `merge_id: string`.
  - `EventsParams` (`events.list`): add `merge_id: "string?"` so a Merged Chat timeline loads through `events.list`.
- **New methods added to `protocol.json` and wired in `rpc/`:**
  - `room.info` (`RoomInfoParams {room_id: string, refresh?: bool}` → `RoomInfoResult`)
  - `room.setLocalOverride` (`RoomLocalOverrideParams {room_id: string, local_name: string, local_avatar_path: string}` → `Empty`)
  - `room.export` (`RoomExportParams {room_id: string, path: string}` → `RoomExportResult {messages_written: int}`)
  - `room.reportSpam` (`ReportSpamParams {room_id: string, leave_or_delete?: bool}` → `Empty`)
  - `room.setName` (`RoomTextParams {room_id: string, text: string}` → `Empty`)
  - `room.setTopic` (`RoomTextParams {room_id: string, text: string}` → `Empty`)
  - `room.setAvatar` (`RoomAvatarParams {room_id: string, path: string}` → `Empty`)
  - `room.invite` (`RoomInviteParams {room_id: string, user_ids: string[]}` → `Empty`)
  - `room.kick` (`RoomKickParams {room_id: string, user_id: string, reason?: string}` → `Empty`)
  - `room.setAdmin` (`RoomAdminParams {room_id: string, user_id: string, is_admin: bool}` → `Empty`)
  - `room.leave` (`RoomParams {room_id: string}` → `Empty`)
  - `room.delete` (`RoomParams {room_id: string}` → `Empty`)
  - `people.contacts` (`PeopleContactsParams {network?: string, account_id?: string, query?: string}` → `PeopleContactsResult {contacts: ContactCandidate[]}`)
  - `people.resolve` (`PeopleResolveParams {network: string, account_id?: string, identifier: string, start_chat?: bool}` → `ContactCandidate`)
  - `room.createGroup` (`CreateGroupParams {network: string, account_id?: string, name: string, user_ids: string[]}` → `RoomResult {room_id: string}`)
  - `blast.send` (`BlastSendParams {room_ids: string[], text: string}` → `BlastSendResult {events: Event[]}`)
  - `merge.create` (`MergeCreateParams {name: string, room_ids: string[]}` → `MergedChat`)
  - `merge.update` (`MergeUpdateParams {merge_id: string, name: string, room_ids: string[], last_room_id?: string}` → `MergedChat`)
  - `merge.delete` (`MergeDeleteParams {merge_id: string}` → `Empty`)
  - `merge.list` (`Empty` → `MergeListResult {merged_chats: MergedChat[]}`)
  - `merge.suggest` (`Empty` → `MergeSuggestResult {suggestions: MergeSuggestion[]}`)

**Steps:**
- [ ] **Step 1: Write failing RPC and conformance tests in `conformance_test.go`, `presence_test.go`, and `organise_test.go`.**
  - Update `conformance_test.go` to require `ProtocolVersion == 6` and validate `room-info.json`, `people-resolve.json`, and `merge-create.json`.
  - Add `TestRPCRoomInfoGroupActionsAndReportSpam` (`presence_test.go`) asserting `room.info`, `room.setLocalOverride`, `room.setName`, `room.invite`, `room.kick`, `room.setAdmin`, `room.reportSpam`, `people.resolve`, `room.createGroup`, and `blast.send` round-trip over JSON-RPC.
  - Add `TestRPCMergedChatsAndEventsList` (`organise_test.go`) asserting `merge.create`, `merge.list`, `merge.suggest`, `events.list` with `merge_id`, and `merge.delete` round-trip over JSON-RPC.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/rpc:rpc_test` and confirm failure.**
- [ ] **Step 3: Update `protocol.json`, add example files, and implement the RPC handlers in `rpc/`.**
  - Run `bazel run //:gazelle` if `BUILD.bazel` needs `people.go`.
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/engine/internal/rpc:rpc_test` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 7.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): bump protocol to v6 with chat info, group, people, and merge RPCs" apps/desktop/courier/protocol apps/desktop/courier/engine/internal/rpc`

---

### Task 8: `CourierCore` Protocol 6 Models, Timeline Membership Grouping, and Quick-Reply Variables

**Files:**
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ChatFeatures.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Timeline.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ConversationModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerPreferences.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/QuickReplies.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/EngineMessageSender.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/InboxModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/AppModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/CommandSet.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ProtocolConformanceTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/TimelineTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ConversationModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/QuickRepliesTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/CommandSetTests.swift`

**Interfaces:**
- Bump `public static let protocolVersion = 6` in `Protocol.swift` and add Swift `Codable, Sendable, Equatable` types matching Task 7 (`RoomInfoResult`, `RoomLink`, `ContactCandidate`, `MergedChat`, `MergeSuggestion`, plus the extended fields on `ChatFeatures`, `Member`, `InboxRow`, and `DirectChatParams`).
- In `Timeline.swift`:
  - Add `TimelineItem.membershipRun(id: String, events: [Event], summary: String)` that collapses consecutive `m.room.member` events into a single centered status line (e.g. `"Alice joined the group"`, or `"Alice and 2 others joined the group"` when `events.count == 3`) when `ComposerPreferences.showChatUpdatesInTimeline` is `true`, and hides them when `false`.
- In `QuickReplies.swift`:
  - Add `public struct QuickReplyContext: Sendable, Equatable { public var recipientFullName: String; public var senderFullName: String }` with computed `recipientFirstName` and `senderFirstName` (splitting on the first whitespace).
  - Add `public static func expand(_ body: String, context: QuickReplyContext) -> String` replacing `{recipient.firstName}`, `{recipient.fullName}`, `{sender.firstName}`, and `{sender.fullName}`.
- In `CommandSet.swift`:
  - Add command IDs `"conversation.toggleChatInfo"` (`⌘I`), `"conversation.searchChatInfo"` (`⌘⇧I`), `"conversation.toggleCalendar"` (`⌘⌥K`), `"conversation.showSenderCard"` (`⌘⇧O`), and `"inbox.newGroupOrBlast"` (`⌘⇧N`).

**Steps:**
- [ ] **Step 1: Write failing tests in `ProtocolConformanceTests.swift`, `ChatFeaturesTests.swift`, `TimelineTests.swift`, `QuickRepliesTests.swift`, `ConversationModelTests.swift`, and `CommandSetTests.swift`.**
  - `ProtocolConformanceTests`: decodes `room-info.json`, `people-resolve.json`, and `merge-create.json` and verifies `ProtocolVersion == 6`.
  - `TimelineTests.testConsecutiveMembershipEventsCollapseAndRespectToggle`: feeds 3 consecutive `m.room.member` join events (`Alice`, `Bob`, `Carol`) and asserts `Timeline.build(..., showChatUpdates: true)` produces 1 `.membershipRun` with `summary == "Alice and 2 others joined the group"`, and `Timeline.build(..., showChatUpdates: false)` omits the `.membershipRun`.
  - `QuickRepliesTests.testExpandsRecipientAndSenderVariables`: calls `QuickReplies.expand("Hi {recipient.firstName} ({recipient.fullName}), from {sender.firstName} / {sender.fullName}", context: .init(recipientFullName: "Alice Example", senderFullName: "Sam Example"))` and asserts the result equals `"Hi Alice (Alice Example), from Sam / Sam Example"`.
  - `ConversationModelTests.testMergedChatComposerDefaultsToLastMessageNetworkAndSwitches`: loads a `MergedChat` with `lastRoomID: "!sig:courier.local"` and asserts `model.activeReplyRoomID == "!sig:courier.local"`, then calls `model.cycleMergedReplyNetwork()` and asserts `model.activeReplyRoomID == "!wa:courier.local"`.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests` and confirm failure.**
- [ ] **Step 3: Implement the `CourierCore` updates.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 8.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): update CourierCore for protocol v6, membership runs, and quick-reply variables" apps/desktop/courier/app/Sources/CourierCore apps/desktop/courier/app/Tests/CourierCoreTests`

---

### Task 9: App — Chat Info Right Pane (`⌘I` / `⌘⇧I`), Standalone Window, Bookmarks Tab, Export Chat, and Membership Timeline Rows

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/ChatInfoPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationCommands.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessagesSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/App.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/Fixtures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- `public struct ChatInfoPane: View` (`width: 280`):
  - Header: avatar (`AvatarView`), title + edit pencil button, network pill, handle/phone/timezone in 1:1 chats (`Member.identifiers` + `Member.tz`), member count in groups, and an open-in-separate-window button (`openWindow(id: "chat-info", value: info.roomID)`).
  - Filter field (`@FocusState` focused by `⌘⇧I`) filtering participants, links, files, and bookmarks.
  - Collapsible sections:
    - **Participants** (groups only): avatar, name, admin badge (`"Admin"` when `member.isAdmin`), bot badge (`"Bot"` when `member.isBot`), plus **Add Participants** button when `info.features.canInvite`.
    - **Shared Media** (`3×3` thumbnail grid from `info.sharedMedia`), **Files** (`info.sharedFiles`), **Links** (`info.sharedLinks`), **Bookmarks** (loaded via existing `search.query` with `sections: ["bookmarks"], filters: .init(roomIDs: [info.roomID])`), and **Pinned** (`info.pinnedEventIDs`).
    - **Encryption** row (`"Encrypted"` with lock icon when `info.encrypted`, else `"Transport TLS"`), **Disappearing Messages** row (reusing `DisappearingMenu` and `room.setDisappearing`), **Refresh Chat Info** button (`room.info` with `refresh: true`), and **Export Chat…** button (`NSSavePanel` → `room.export`).
- In `MessagesSettingsPane.swift`: add Toggle **"Show chat updates in timeline"** bound to `ComposerPreferences.showChatUpdatesInTimeline`.

**Steps:**
- [ ] **Step 1: Write failing snapshot tests in `ViewSnapshotTests.swift`.**
  - Add `testChatInfoPaneDirectChatLightAndDark` (`width: 280, height: 640`, asserting `ChatInfoPane` renders a 1:1 DM with phone number `+1 555-010-0101`, timezone `America/Los_Angeles`, Shared Media, Links, Bookmarks, and Encryption rows).
  - Add `testChatInfoPaneGroupWithAdminsLightAndDark` (`width: 280, height: 640`, asserting `ChatInfoPane` renders a group with 3 members, `Admin` badge, **Add Participants** button, and Disappearing Messages row).
  - Add `testTimelineMembershipRunRowLightAndDark` (`width: 520, height: 120`, asserting a centered pill `"Alice and 2 others joined the group"`).
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `ChatInfoPane.swift` and wire it into `MainWindow.swift`, `ConversationView.swift`, `MessageBubble.swift`, `ConversationCommands.swift`, `MessagesSettingsPane.swift`, and `App.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 9.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add Chat Info pane, standalone window, export, and membership timeline rows" apps/desktop/courier/app`

---

### Task 10: App — Edit Group (**For Everyone** vs **Just for Me**), Participant Context Menu, Add Participants, Leave, Delete, and Report as Spam

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/EditGroupSheet.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatContextMenu.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ConversationModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/Fixtures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `EditGroupSheet.swift`:
  - `public struct EditGroupSheet: View`:
    - Segmented scope picker: **For Everyone** (enabled only when `features.canSetName || features.canSetAvatar || features.canSetTopic`) vs **Just for Me** (always enabled, even in 1:1 chats and Google Messages groups). When **For Everyone** is unavailable, the picker defaults to **Just for Me** with caption `"Changes apply only on this Mac."`
    - Name text field, Topic text field (shown in **For Everyone** when `features.canSetTopic`), avatar picker + **Reset to Network Default** button (calls `room.setLocalOverride` with `local_name: "", local_avatar_path: ""`).
  - `public struct AddParticipantsSheet: View`: search field querying `people.contacts` + `search.query(sections: ["in_groups"])`, multi-select chips, and **Add** button calling `room.invite`.
  - `public struct ReportSpamSheet: View`:
    - Confirmation text: `"Hide this chat on this Mac and mark it as spam?"`
    - Optional checkbox (`@State private var alsoLeaveOrDelete = false` — **unticked by default**):
      - In a group where `features.canLeave` is `true`: `"Also leave the group on <Network>"`
      - In a chat where `features.canDelete` is `true`: `"Also delete the chat on <Network>"`
      - When both `canLeave` and `canDelete` are `false`: no checkbox is shown.
    - **Report Spam** button calling `room.reportSpam(room_id: roomID, leave_or_delete: alsoLeaveOrDelete)`.
  - `public struct ParticipantContextMenu: View`:
    - **Message `<Name>`** (`room.directChat` with `room_id` + `user_id`)
    - **Make Admin** / **Remove Admin** (shown when `features.canSetAdmin`)
    - **Remove from Group** (shown when `features.canKick`)
    - **Copy User ID**

**Steps:**
- [ ] **Step 1: Write failing model and snapshot tests in `ConversationModelTests.swift` and `ViewSnapshotTests.swift`.**
  - `ConversationModelTests.testEditGroupSavesForEveryoneOrJustForMe`: asserts saving with `.forEveryone` dispatches `room.setName` and `room.setTopic`, while saving with `.justForMe` dispatches `room.setLocalOverride`.
  - `ConversationModelTests.testReportSpamSheetDefaultsLeaveOrDeleteToFalse`: asserts `ReportSpamDraft(roomID: "!g:courier.local", canLeave: true, canDelete: false)` initializes `alsoLeaveOrDelete == false`, sends `leave_or_delete: false` when confirmed untouched, and sends `leave_or_delete: true` when toggled on.
  - `ViewSnapshotTests.testEditGroupSheetAndReportSpamSheetLightAndDark`: renders `EditGroupSheet` (both **For Everyone** enabled and **Just for Me** locked) and `ReportSpamSheet` (showing the unticked `"Also leave the group on WhatsApp"` checkbox) in light and dark mode.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `EditGroupSheet.swift`, participant context menu, and `ChatContextMenu.swift` actions.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 10.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add EditGroupSheet, AddParticipantsSheet, ReportSpamSheet, and member actions" apps/desktop/courier/app`

---

### Task 11: App — New Chat, New Group, Blasts (`⌘N` / `⌘⇧N`), and Merged Chats UI

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/StartNewChatView.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/MergedChatEditorSheet.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/InboxCommands.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/InboxRow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatContextMenu.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/InboxModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/Fixtures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- `public struct StartNewChatView: View`:
  - Triggered by `⌘N` (starts in 1:1 mode) or `⌘⇧N` (starts with multi-select token bar open).
  - Account/network filter pill bar (All Networks, or a specific connected account).
  - Search field querying local chats/group members (`search.query`) + bridge contacts (`people.contacts`). When the query looks like a phone number (`+...` or `>= 7` digits) or `@username`, shows an action row **"Look up `<query>` on `<Network>`"** calling `people.resolve`.
  - When `>= 2` recipients are selected in the token bar, shows a mode segmented control:
    - **New Group** (enabled when all selected recipients are on one account whose bridge implements `CreateGroupHandlingNetworkAPI`, which is all five today; Google Messages needs 2+ other people, and on Slack this makes a group DM of 2 to 8 people) with a Group Name field → calls `room.createGroup`.
    - **Blast (Separate 1:1 Messages)** (works across any mix of networks) with a message composer → calls `blast.send`.
- `public struct MergedChatEditorSheet: View`:
  - Triggered from `ChatContextMenu` (**Merge with Another Chat…**) or `ChatInfoPane`.
  - Shows automatic suggestions from `merge.suggest` at the top, a search list of 1:1 chats to check/uncheck, a merged display name field, and **Merge Chats** / **Unmerge** buttons (`merge.create`, `merge.update`, `merge.delete`).
- In `InboxRow.swift` and `ComposerView.swift`:
  - Merged inbox rows render stacked network badges for each member network.
  - In a Merged Chat conversation, `ComposerView` renders a clickable network pill (`⌘L` cycles networks) showing which network and account the reply will be sent from (`model.activeReplyRoomID`), and `MessageBubble` shows a small network badge on each message bubble.

**Steps:**
- [ ] **Step 1: Write failing tests in `InboxModelTests.swift` and `ViewSnapshotTests.swift`.**
  - `InboxModelTests.testStartNewChatSwitchesBetweenDMGroupAndCrossNetworkBlast`: selects 1 recipient and asserts mode is `.directChat`; adds a second recipient on the same network and asserts `.newGroup` and `.blast` are both enabled; adds a third recipient on a different network and asserts `.newGroup` is disabled (`reason: "Group members must be on the same network"`) while `.blast` remains enabled.
  - `ViewSnapshotTests.testStartNewChatAndBlastViewLightAndDark`: snapshots `StartNewChatView` in 1:1 lookup mode and multi-recipient **New Group / Blast** mode (`width: 520, height: 480`).
  - `ViewSnapshotTests.testMergedChatInboxRowComposerAndEditorLightAndDark`: snapshots a merged `InboxRow`, the merged `ComposerView` network pill, and `MergedChatEditorSheet` with suggestions (`width: 480, height: 460`).
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `StartNewChatView.swift`, `MergedChatEditorSheet.swift`, and wire `InboxRow.swift`, `ChatContextMenu.swift`, `ComposerView.swift`, `InboxCommands.swift`, and `MainWindow.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 11.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add StartNewChatView, New Group, Blasts, and Merged Chats UI" apps/desktop/courier/app`

---

### Task 12: App — Sender Hover Card (`⌘⇧O`) and macOS `Contacts.framework` Integration

**Files:**
- Modify: `apps/desktop/courier/app/Resources/Info.plist`
- Create: `apps/desktop/courier/app/Sources/CourierCore/ContactsBridge.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/UserHoverCard.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationCommands.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/ContactsBridgeTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/Fixtures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `apps/desktop/courier/app/Resources/Info.plist`, add:
  ```xml
  <key>NSContactsUsageDescription</key>
  <string>Courier matches people in your chats with your contacts and lets you save new contacts on this Mac. Your contacts never leave this Mac.</string>
  ```
- In `CourierCore/ContactsBridge.swift`:
  ```
  public enum ContactsAuthStatus: String, Sendable, Equatable {
      case notDetermined, authorized, denied, restricted
  }

  public struct MatchedContact: Sendable, Equatable {
      public var contactIdentifier: String
      public var fullName: String
      public var organization: String
      public var phones: [String]
      public var emails: [String]
  }

  public protocol ContactsStoreProtocol: Sendable {
      func authorizationStatus() -> ContactsAuthStatus
      func requestAccess() async -> Bool
      func match(identifiers: [String], fallbackName: String) -> MatchedContact?
      func saveNewContact(givenName: String, familyName: String, phone: String?, email: String?) throws -> MatchedContact
  }
  ```
  - Phone normalization strips spaces, dashes, and parentheses so `tel:+15550100101` matches `+1 (555) 010-0101`.
  - When `authorizationStatus()` is `.denied` or `.restricted`, `ContactsBridge` never calls `requestAccess()` again and exposes `isAccessDenied == true`.
- In `Courier/UserHoverCard.swift`:
  - Triggered by hovering a sender avatar/name in `MessageBubble` (`300ms` hover delay) or pressing `⌘⇧O` on the selected message.
  - Shows avatar, display name, network badge, formatted phone/username/email identifiers, timezone local time, shared groups (from `search.query(sections: ["in_groups"])`), **Message** button (`room.directChat`), **Copy Handle** button, and:
    - When `ContactsAuthStatus == .authorized` and matched: **"In Contacts: `<fullName>`"** badge.
    - When `ContactsAuthStatus == .authorized` or `.notDetermined` and unmatched: **"Save to Contacts…"** inline form (`Given Name`, `Family Name`, `Phone`, `Email`).
    - When `ContactsAuthStatus == .denied` or `.restricted`: a non-blocking banner **"Contacts access is turned off in System Settings."** with an **Open System Settings** button (`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!)`).

**Steps:**
- [ ] **Step 1: Write failing tests in `ContactsBridgeTests.swift` and `ViewSnapshotTests.swift`.**
  - `ContactsBridgeTests.testMatchesNormalizedPhoneAndEmail`: injects a `FakeContactsStore` with contact `"Alice Example"` (`phone: "+1 (555) 010-0101"`, `email: "alice@example.com"`), queries `match(identifiers: ["tel:+15550100101"], fallbackName: "Alice")`, and asserts `matched?.fullName == "Alice Example"`.
  - `ContactsBridgeTests.testDeniedAuthorizationDoesNotPromptAndReportsDenied`: injects `FakeContactsStore(status: .denied)` and asserts `bridge.status == .denied`, `requestAccessCalls == 0`, and `bridge.matchedContact == nil`.
  - `ContactsBridgeTests.testSaveNewContactPersistsAndReturnsMatchedContact`: calls `saveNewContact(givenName: "Bob", familyName: "Carter", phone: "+15550100202", email: nil)` and asserts the returned `MatchedContact.fullName == "Bob Carter"`.
  - `ViewSnapshotTests.testUserHoverCardAuthorizedAndDeniedLightAndDark`: snapshots `UserHoverCard` in both `.authorized` (with shared groups and **Save to Contacts…** button) and `.denied` (showing `"Contacts access is turned off in System Settings."` and **Open System Settings** button) in light and dark mode (`width: 300, height: 320`).
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Add `NSContactsUsageDescription` to `Info.plist`, implement `ContactsBridge.swift` and `UserHoverCard.swift`, and run `bazel run //:gazelle` if needed.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 12.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add UserHoverCard and Contacts.framework integration" apps/desktop/courier/app`

---

### Task 13: App — Calendar Right Pane (`⌘⌥K`) and Detected Dates in Messages (`EventKit` + `NSDataDetector`)

**Files:**
- Modify: `apps/desktop/courier/app/Resources/Info.plist`
- Create: `apps/desktop/courier/app/Sources/CourierCore/CalendarBridge.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/CalendarPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationCommands.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/CalendarBridgeTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/Fixtures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `apps/desktop/courier/app/Resources/Info.plist`, add:
  ```xml
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Courier shows your schedule in the calendar pane and lets you add events from dates in your messages. Your calendar never leaves this Mac.</string>
  ```
- In `CourierCore/CalendarBridge.swift`:
  ```swift
  public enum CalendarAuthStatus: String, Sendable, Equatable {
      case notDetermined, fullAccess, denied, restricted
  }

  public struct CalendarEventItem: Identifiable, Sendable, Equatable {
      public var id: String
      public var title: String
      public var startDate: Date
      public var endDate: Date
      public var isAllDay: Bool
      public var calendarColorHex: String
      public var location: String?
      public var meetingURL: URL?
  }

  public struct DetectedMessageDate: Sendable, Equatable {
      public var range: Range<String.Index>
      public var matchedText: String
      public var startDate: Date
      public var durationSeconds: TimeInterval
  }

  public protocol CalendarStoreProtocol: Sendable {
      func authorizationStatus() -> CalendarAuthStatus
      func requestFullAccess() async -> Bool
      func events(forDay day: Date) -> [CalendarEventItem]
      func createEvent(title: String, startDate: Date, endDate: Date, notes: String?) throws -> CalendarEventItem
  }
  ```
  - `CalendarBridge.extractMeetingURL(from text: String) -> URL?` matches `https://` URLs on `meet.google.com`, `zoom.us` (`*.zoom.us`), `teams.microsoft.com`, and `webex.com` (`*.webex.com`).
  - `CalendarBridge.detectDates(in text: String, referenceDate: Date) -> [DetectedMessageDate]` uses `NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)` (defaulting `durationSeconds` to `3600` when the detector returns `0`).
- In `Courier/CalendarPane.swift` (`width: 280`, toggled by `⌘⌥K`):
  - Day navigation header (`Previous Day`, `Today`, `Next Day`, date label).
  - When `CalendarAuthStatus == .fullAccess`: chronological list of `CalendarEventItem` rows with color bar, time range, title, and a **Join** button when `meetingURL != nil`.
  - When `CalendarAuthStatus == .denied` or `.restricted`: a non-blocking view showing **"Calendar access is turned off in System Settings."** and an **Open System Settings** button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`).
- In `MessageBubble.swift`: detected dates render with a dashed underline; clicking one opens a popover (`AddCalendarEventPopover`) pre-filled with the message text as title, start/end time, and an **Add to Calendar** button calling `createEvent`.

**Steps:**
- [ ] **Step 1: Write failing tests in `CalendarBridgeTests.swift` and `ViewSnapshotTests.swift`.**
  - `CalendarBridgeTests.testExtractsVideoMeetingURLs`: asserts `"Join at https://meet.google.com/abc-defg-hij or https://acme.zoom.us/j/12345"` extracts `https://meet.google.com/abc-defg-hij` and ignores non-meeting URLs like `https://example.com`.
  - `CalendarBridgeTests.testDetectsDatesInMessageText`: calls `CalendarBridge.detectDates(in: "Let's meet on 2026-10-25 at 14:30 UTC", referenceDate: refDate)` and asserts `detected.count == 1`, `detected[0].matchedText.contains("2026-10-25")`, and `detected[0].durationSeconds == 3600`.
  - `CalendarBridgeTests.testDeniedCalendarAccessDoesNotPromptAndReportsDenied`: injects `FakeCalendarStore(status: .denied)` and asserts `bridge.status == .denied`, `requestAccessCalls == 0`, and `bridge.events == []`.
  - `ViewSnapshotTests.testCalendarPaneAuthorizedAndDeniedLightAndDark`: snapshots `CalendarPane` in `.fullAccess` (with 2 events, one with a **Join** button) and `.denied` (showing `"Calendar access is turned off in System Settings."` and **Open System Settings** button) in light and dark mode (`width: 280, height: 520`).
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Add `NSCalendarsFullAccessUsageDescription` to `Info.plist`, implement `CalendarBridge.swift` and `CalendarPane.swift`, and wire `MainWindow.swift`, `MessageBubble.swift`, and `ConversationCommands.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 13.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add CalendarPane, EventKit bridge, and message date detection" apps/desktop/courier/app`

---

### Task 14: Final Checks, `m4-acceptance.md` 4.5a Update, and James's By-Hand Check

**Files:**
- Modify: `apps/desktop/courier/docs/m4-acceptance.md`

**Steps:**
- [ ] **Step 1: Update `apps/desktop/courier/docs/m4-acceptance.md` with the §4.5a acceptance checklist (naming every `anchor` + `item` row from `## Ledger Coverage` below under `Keys`, `Settings`, `Menus`, `Components`, `Commands`, and `Carried to later parts` in the §4.4 style) and move the completed 4.4 carried item ("Starting a chat with someone who is not in a group with you") into §4.5a.**
- [ ] **Step 2: Run the full automated verification suite via Bazel.**
  - Run:
    ```sh
    bazel run //:tidy
    bazel run //:gazelle
    bazel test //apps/desktop/courier/...
    bazel build --config=macos-app //apps/desktop/courier/app:Courier
    aspect lint //apps/desktop/courier/...
    bazel run //tools/secret-scan
    ```
  - Expected: all engine Go tests, protocol conformance tests, `CourierCoreTests`, `CourierViewTests` (light + dark PNG snapshots), macOS app bundle build, lint, and secret scan exit `0`.
- [ ] **Step 3: Commit the acceptance doc update.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "docs(courier): record milestone 4.5a acceptance checklist" apps/desktop/courier/docs/m4-acceptance.md`
- [ ] **Step 4: James's by-hand check (live networks on the Mac).**
  1. Launch the built app bundle (`bazel build --config=macos-app //apps/desktop/courier/app:Courier`) against your live `courier.db`.
  2. Press `⌘I` in a 1:1 chat and a group chat: verify participant phone/username/timezone metadata, Shared Media/Files/Links/Bookmarks sections, and Disappearing Messages.
  3. Rename a Google Messages chat with **Just for Me** and verify the custom name persists across app restarts without touching the remote network; rename a WhatsApp/Signal test group with **For Everyone** and verify the remote group title updates.
  4. Press `⌘N`, look up a phone number or `@username` of someone not in any group with you, and verify a 1:1 DM opens; press `⌘⇧N`, select two people on different networks, send a Blast using a quick reply with `{recipient.firstName}`, and verify each recipient receives their own personalized 1:1 message.
  5. Merge two 1:1 chats for the same person across two networks, verify the interleaved timeline and `⌘L` network switcher in the composer, then unmerge.
  6. Hover a sender avatar or press `⌘⇧O` to verify the hover card and Contacts match; press `⌘⌥K` to verify the Calendar right pane, a **Join** button on a video call, and clicking a detected date in a message bubble.

---

## Ledger Coverage (`docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv`)

### Covered in Milestone 4.5a (this plan — 38 rows)
- `component AddContactForm.tsx` → **Task 12** (inline **Save to Contacts…** form in `UserHoverCard`)
- `component BrandChatInfoPaneBookmarks.tsx` → **Task 9** (**Bookmarks** collapsible section in `ChatInfoPane`)
- `component BrandUserHoverCard.tsx` → **Task 12** (`UserHoverCard` on sender avatar/name hover or `⌘⇧O`)
- `component CalendarPane.tsx` → **Task 13** (`CalendarPane` right sidebar `⌘⌥K` and detected-date event creation)
- `component CommandBarUser.tsx` → **Tasks 5, 11** (person row in `StartNewChatView` and starting a 1:1 DM with someone from `In groups`)
- `component ContactItem.tsx` → **Tasks 10, 11** (contact row in `StartNewChatView` and `AddParticipantsSheet`)
- `component CopyableField.tsx` → **Tasks 9, 10, 12** (copyable phone/username/email/user ID in `ChatInfoPane`, `ParticipantContextMenu`, and `UserHoverCard`)
- `component CreateMergedChatBrowserWindow.tsx` → **Task 11** (`MergedChatEditorSheet`)
- `component DraftChatAvatar.tsx` → **Task 11** (draft recipient avatar in `StartNewChatView`)
- `component EditGroupBrowserWindow.tsx` → **Task 10** (`EditGroupSheet`)
- `component EditGroupModal.tsx` → **Tasks 1, 3, 4, 10** (`EditGroupSheet` **For Everyone** vs **Just for Me** local override)
- `component Email.tsx` → **Tasks 9, 12** (email identifiers in `ChatInfoPane` and `UserHoverCard`)
- `component GroupParticipantItem.tsx` → **Tasks 2, 4, 9, 10** (participant rows, admin/bot badges, `ParticipantContextMenu`, and `AddParticipantsSheet`)
- `component GroupTitleBar.tsx` → **Task 11** (group name and avatar header when creating a group in `StartNewChatView`)
- `component HoverCard.context.tsx` → **Task 12** (`UserHoverCard` presentation state)
- `component HoverCard.tsx` → **Task 12** (`UserHoverCard` popover container)
- `component MembershipGrouper.tsx` → **Tasks 2, 8, 9** (`TimelineItem.membershipRun` collapsing consecutive `m.room.member` events)
- `component MergeSuggestionNetworkIcons.tsx` → **Tasks 6, 11** (network badges on `SuggestMergedChats` rows in `MergedChatEditorSheet`)
- `component MergedChatEditor.tsx` → **Tasks 6, 7, 11** (`MergedChatEditorSheet` and `merge.create` / `merge.update` / `merge.delete` / `merge.list` / `merge.suggest`)
- `component PhoneNumber.tsx` → **Tasks 2, 9, 12** (`tel:` phone identifiers in `ChatInfoPane` and `UserHoverCard`)
- `component ProfileField.tsx` → **Tasks 2, 9, 12** (handle, phone, and timezone profile rows in `ChatInfoPane` and `UserHoverCard`)
- `component QuickReplyItem.tsx` → **Task 8** (`{recipient.firstName}`, `{recipient.fullName}`, `{sender.firstName}`, `{sender.fullName}` variable expansion for 1:1 chats and Blasts)
- `component RightPane.tsx` → **Tasks 9, 13** (right-pane slot hosting `ChatInfoPane` and `CalendarPane`)
- `component StackedAvatars.tsx` → **Task 11** (stacked network/member badges on Merged Chat rows in `InboxRow`)
- `component StartNewChatView.tsx` → **Tasks 5, 7, 11** (`StartNewChatView` for 1:1 DMs, **New Group**, and **Blast**)
- `component TextAreaAutocomplete.tsx` → **Task 11** (Merged Chat composer reply-network pill and `⌘L` switcher in `ComposerView`)
- `component ThreadDescription.tsx` → **Tasks 3, 9, 11** (group topic/description, 1:1 contact details, and merge controls in `ChatInfoPane`)
- `component ThreadInfo.tsx` → **Tasks 3, 7, 9** (`ChatInfoPane` sections: Shared Media, Files, Links, Bookmarks, Participants, Pinned, Encryption, Disappearing Messages, Export Chat, Leave/Delete/Report as Spam)
- `component ThreadInfoBrowserWindow.tsx` → **Task 9** (standalone `"chat-info"` window)
- `component new-chat-utils.tsx` → **Tasks 5, 11** (`people.contacts`, `people.resolve`, and identifier lookup helpers)
- `command Create new chat` → **Tasks 8, 11** (registered in `CommandSet`, opens `StartNewChatView` in 1:1 mode)
- `command Create new group` → **Tasks 8, 11** (registered in `CommandSet`, opens `StartNewChatView` in **New Group / Blast** mode)
- `command Merge chats` → **Tasks 8, 11** (registered in `CommandSet`, opens `MergedChatEditorSheet`)
- `hotkey Chat: Start New` → **Tasks 8, 11** (`⌘N` / `⌘⇧N` opening `StartNewChatView`)
- `hotkey Open User Profile` → **Tasks 8, 12** (`⌘⇧O` opening `UserHoverCard` for the selected message's sender)
- `hotkey Toggle Chat Info` → **Tasks 8, 9** (`⌘I` toggling `ChatInfoPane`, `⌘⇧I` focusing its filter field)
- `setting:appearance Show membership events` → **Tasks 8, 9** (**"Show chat updates in timeline"** toggle in `MessagesSettingsPane` bound to `ComposerPreferences.showChatUpdatesInTimeline`)
- `menu:File New Chat` → **Task 11** (File ▸ New Chat `⌘N` menu command)
- Carried from 4.4 (`apps/desktop/courier/docs/m4-acceptance.md` §4.4): Starting a 1:1 chat with someone not in a group with you → **Tasks 5, 7, 11**

### Carried to Milestone 4.5b (Rich Media Playback & Capture Plan — 45 rows)
- `component AttachmentCarousel.tsx` (full-window media lightbox with zoom, pan, rotate, flip, download, copy, Quick Look)
- `component Audio.tsx` (inline voice-note waveform player, `0.5×–2×` speed, played state)
- `component Autocomplete.tsx` (composer `:` emoji autocomplete popover)
- `component BrandStopButton.tsx` (stop voice-note recording button in composer)
- `component BrandVideo.tsx` (inline video element)
- `component Emoji.tsx` (composer plus-menu media/emoji items)
- `component EmojiItem.tsx` (emoji picker cell)
- `component EnhancedImg.tsx` (inline image view with BlurHash placeholder)
- `component FileAttachment.tsx` (attachment chip and downloadable file card)
- `component FileDropOverlay.tsx` (drag-and-drop file attachment overlay)
- `component FilePlaceholder.tsx` (Audio / PDF / Text / Document placeholder card)
- `component FileRowSpinner.tsx` (attachment loading indicator)
- `component GalleryGrouper.tsx` (consecutive image/video gallery grid in timeline)
- `component GalleryVideoPoster.tsx` (video poster frame in gallery grid)
- `component GifPicker.tsx` (composer GIF picker UI; search provider stubbed in 4.7)
- `component GlobalAudioPlayer.tsx` (persistent floating audio player across chats)
- `component ImageError.tsx` (broken-image fallback card)
- `component LoadingAttachment.tsx` (in-flight attachment placeholder)
- `component Location.tsx` (inline map card with Apple Maps / Google Maps / Copy Location actions)
- `component MediaViewerBrowserWindow.tsx` (Media Viewer window with Media / Links / Docs tabs, Sent By filter, sort, caption search)
- `component MediaWithSender.tsx` (media tile with sender attribution in Media Viewer)
- `component MessageIFrame.tsx` (sandboxed iframe for external embeds)
- `component PDF.tsx` (inline paged PDF viewer)
- `component PDFAttachment.tsx` (PDF attachment card with page controls)
- `component PendingAttachments.tsx` (pending attachment strip in composer)
- `component PictureInPictureBrowserWindow.tsx` (floating Picture-in-Picture video window)
- `component StickerPicker.tsx` (composer sticker picker)
- `component TranscodedAttachment.tsx` (transcoded audio/image attachment view)
- `component ViewLimitedMediaViewer.tsx` (view-once photo, video, and voice-note viewer)
- `command Media viewer` (command bar entry opening the Media Viewer window)
- `hotkey Chat: Send File` (`⌘O` attach file in composer)
- `hotkey Download Attachments` (`⌘D` download attachments on selected message)
- `hotkey Message: Record Audio` (`⌘⇧A` record voice note in composer)
- `hotkey Message: Send GIF` (`⌘⇧G` open GIF picker)
- `hotkey Message: Send Sticker` (`⌘⌥⇧S` open sticker picker)
- `setting:appearance Disable link previews in outgoing messages` (suppress outgoing link preview cards)
- `setting:appearance Load external embeds automatically` (auto-load external embeds vs click-to-load)
- `setting:general Always ask where to save files before downloading` (prompt for destination on attachment download)
- `setting:general Automatically play the next voice note` (continuous playback across consecutive voice notes)
- `setting:general Automatically send GIFs after selection` (send picked GIF immediately vs attach to draft)
- `setting:general Disable automatic replacement of emoticons with emojis` (toggle `:)` → `🙂` replacement in composer)
- `setting:general Downloads location <path>` (default attachment download folder)
- `setting:general Enable emoji autocomplete` (toggle `:` emoji autocomplete in composer)
- `setting:general Microphone` (recording input device selector for voice notes)
- `menu:File Open…` (File ▸ Open… `⌘O` attach file menu item)

### Not Planned or Later Milestones (14 rows)
- `command Join a Matrix room` — Dropped in Iteration 1 (`2026-10-15-courier-iteration-1-design.md` §3: Courier runs five non-Matrix bridges with no generic Matrix room join).
- `command Open space in new window` — Deferred to Milestone 4.6 window management.
- `command Profile` — Dropped in Iteration 1 (`2026-10-15-courier-iteration-1-design.md` §3: no Beeper cloud account profile pane).
- `component ChangeEmailBrowserWindow.tsx` — Dropped in Iteration 1 (`2026-10-15-courier-iteration-1-design.md` §3: no Beeper cloud account email management).
- `component ChatThemeBrowserWindow.tsx` — Deferred to Milestone 4.7 (Appearance, wallpapers, and per-chat themes).
- `component ChatThemeWindow.tsx` — Deferred to Milestone 4.7 (Appearance, wallpapers, and per-chat themes).
- `component DeleteAccountModal.tsx` — Dropped in Iteration 1 (`2026-10-15-courier-iteration-1-design.md` §3: no Beeper cloud account deletion).
- `component DeleteAccountPrompt.tsx` — Dropped in Iteration 1 (`2026-10-15-courier-iteration-1-design.md` §3: no Beeper cloud account deletion).
- `component ThreadedRepliesBrowserWindow.tsx` — Thread replies open in the right-hand `ThreadPane` (4.3); detached thread windows are deferred to Milestone 4.6 window management.
- `hotkey Message: Talk to Type` — Deferred to Milestone 4.7 (`AIProvider` dictation stub).
- `menu:File Open Chat in New Window` — Deferred to Milestone 4.6 window management (along with double-click chat "Open in New Window").
- `setting:ai Use OpenAI's Whisper model for Talk to Type and transcribing` — Deferred to Milestone 4.7 (`AIProvider` voice-note transcription stub).
- `setting:general Show Telegram Topics as separate spaces` — Not planned in Iteration 1 (`mautrix-telegram` does not expose forum topics as separate portal spaces).
- `setting:general Show WhatsApp Communities as separate spaces` — Not planned in Iteration 1 (`mautrix-whatsapp` bridges community rooms directly without a separate space hierarchy).
