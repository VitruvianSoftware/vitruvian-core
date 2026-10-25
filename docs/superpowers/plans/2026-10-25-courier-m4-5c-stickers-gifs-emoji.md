# Courier Milestone 4.5c (Stickers, GIFs and Emoji) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Courier's stickers, GIFs, and composer emoji slice (4.5c): `:` emoji autocomplete and `:)` emoticon replacement in the composer, custom emoji and sticker catalog (recent, user-imported, and bridge-synced packs), the sticker picker (`⌘⌥⇧S`), the GIF picker (`⌘⇧G` and `/gif` slash command) backed by an explicit offline `GIFProvider` stub (no third-party GIF service), per-network sticker and GIF sending over mautrix `bridgev2`, borderless sticker and looping GIF timeline rendering, and the three `General → Composing` settings toggles.

**Architecture:** Milestone 4.5 (Media & Voice) was split in `2026-10-25-courier-m4-5a-voice-notes.md` and `2026-10-25-courier-m4-5b-media.md` into three focused milestones: **4.5a** (Voice Notes, merged on `main`), **4.5b** (Photos, Videos, Files, Media Viewer, Link Previews & Downloads, in flight in parallel), and **4.5c** (Stickers, GIFs and Emoji — this plan). This plan is written against `main` as it stands today and names any touchpoint with 4.5b explicitly (`needs 4.5b Task N`). In the Go engine, `actions.Features` exposes per-room `sticker` (`event.CapMsgSticker`) and `gif` (`event.CapMsgGIF`) capabilities from each bridge's `GetCapabilities`, `actions.SendSticker` and `actions.SendGIF` write local files into `media.Store` and hand `event.EventSticker` (`m.sticker`) or `m.video`/`m.image` with `Info.MauGIF = true` (`fi.mau.gif: true`) to `HandleMatrixMessage` through the existing `outbox` undo-send buffer, and `actions.ListStickers` / `actions.ImportSticker` combine recent received/sent stickers from SQLite (`events`), user-imported sticker/emoji files on disk, and remote packs fetched via `bridgev2.StickerImportingNetworkAPI`. In Swift, `EmojiCatalog` and `ComposerModel` drive `:shortcode:` autocomplete and `:)` → `🙂` replacement; `EmojiAutocompletePicker`, `StickerPickerPopover`, and `GIFPickerPopover` (backed by `StubGIFProvider`) attach to the composer toolbar, `+` menu, `/gif` slash command, and `Message` menu hotkeys (`⌘⇧G`, `⌘⌥⇧S`).

**Tech Stack:** Go 1.26 (`engine/internal/{actions,media,rpc,store}`, `maunium.net/go/mautrix` v0.31.0 `bridgev2` + `event`), SQLite (`modernc.org/sqlite`), Swift 6 / SwiftUI + AppKit (`NSTextView`, `NSImageView`, `NSOpenPanel`, `ImageIO`, `UniformTypeIdentifiers`) targeting macOS 14.0 (`apps/desktop/courier/app/BUILD:136`).

---

## Summary for the Owner

### Today (on `main` after 4.5a; 4.5b in flight in parallel)
- **Engine media & sending (`engine/internal/media/media.go`, `engine/internal/actions/actions.go`):** `media.Store` stores content-addressed files under `<dataDir>/media/ab/<sha256>.<ext>` and serves `courier://media/<sha256>.<ext>`. `actions.SendVoice` (`actions.go:730`) shows the full media-send pattern: stage bytes into `media.Store`, build `&event.MessageEventContent`, store an `events` row with `outbox` undo-send hold (`outbox.go:19`), and dispatch `Room.HandleMatrixMessage`. (In parallel, `4.5b Task 2` adds `actions.SendFile` for general image/video/file attachments.)
- **Room features (`engine/internal/actions/features.go`, `app/Sources/CourierCore/ChatFeatures.swift`):** `actions.Features` inspects `caps.File[event.CapMsgVoice]` and produces `RoomFeatures` (`voiceNote`, `FormattingFeatures`, `RichFeatures`). It does **not** yet inspect `caps.File[event.CapMsgSticker]` or `caps.File[event.CapMsgGIF]`. (In parallel, `4.5b Task 1` adds `attachments` for `image`, `video`, and `file`.)
- **Composer & slash commands (`app/Sources/CourierCore/ComposerModel.swift`, `app/Sources/Courier/ComposerView.swift`, `app/Sources/Courier/RichTextView.swift`):** `ComposerModel` already has `@` mention detection (`MentionPicker.swift`) and `/` slash commands (`/shrug`, `/tableflip`, `/unflip`, `/me`, `/spoiler`, `/gif` at `ComposerModel.swift:44-63`), plus a `gifNotice: String?` banner (`ComposerModel.swift:109,327`) that currently says `"GIF search isn't connected yet."` when `/gif` is run. `ComposerView` has a `+` Menu (`ComposerView.swift:262`) that currently lists only slash commands, and a mic/voice button on the trailing side. There is no `:` emoji autocomplete, no `:)` → `🙂` emoticon replacement, no sticker picker, and no GIF picker popover.
- **Settings & hotkeys (`app/Sources/CourierCore/ComposerPreferences.swift`, `app/Sources/Courier/MessagesSettingsPane.swift`, `app/Sources/CourierCore/CommandSet.swift`, `app/Sources/Courier/ConversationCommands.swift`):** `ComposerPreferences` stores `enterSends`, `undoSendHoldSeconds`, and `spellcheckEnabled`. `MessagesSettingsPane` has a `"Composing"` section (`MessagesSettingsPane.swift:31`), but none of the three emoji/emoticon/GIF settings exist yet. `CommandSet` and `ConversationCommands` (`Message` menu) do not yet include `Send GIF` (`⌘⇧G`) or `Send Sticker` (`⌘⌥⇧S`).
- **Timeline (`app/Sources/Courier/MessageBubble.swift`, `app/Sources/CourierCore/Timeline.swift`):** `MessageBubble` renders text, voice notes (`VoiceNoteAttachmentView`), link previews, reactions, and replies. Incoming `m.sticker` events are not yet rendered as borderless stickers, and incoming `m.video`/`m.image` events with `fi.mau.gif: true` are not yetbadged/looped as GIFs. (In parallel, `4.5b Task 6` adds `MediaAttachmentView` for general image/video/file bubbles.)

### What 4.5c adds on top of Today
1. **Per-room Sticker & GIF capability discovery (`room.features`):** `actions.Features` inspects `caps.File[event.CapMsgSticker]` (`m.sticker`) and `caps.File[event.CapMsgGIF]` (`fi.mau.gif`) and returns `StickerFeature` and `GIFFeature` (`supported`, `mime_types`, `max_size`, `captions`). Swift `ChatFeatures` mirrors both and disables sticker/GIF entry points with `"%1$s (Unavailable for %2$s)"` on networks that reject them (e.g. Google Messages and Slack reject `m.sticker`).
2. **Sending stickers & GIFs in the engine (`message.sendSticker`, `message.sendGIF`):**
   - `message.sendSticker` copies a local sticker image (`.webp`, `.png`, `.apng`, `.gif`, `.jpg`) into `media.Store`, reads pixel width/height via Go's standard `image` decoders, preserves optional `fi.mau.bridged_sticker` metadata (`BridgedStickerRef`) so Telegram/Slack stickers keep their native pack identity, records an `m.sticker` (`event.EventSticker`) event in `store` with `hold_ms` undo-send support, and calls `Room.HandleMatrixMessage`.
   - `message.sendGIF` copies a local `.gif` or `.mp4` into `media.Store`, builds an `m.image` (`image/gif`) or `m.video` (`video/mp4`) event with `Info.MauGIF = true` (`"fi.mau.gif": true`), attaches optional `caption`, `reply_to`, and `thread_root`, supports `hold_ms` undo-send, and calls `Room.HandleMatrixMessage`.
3. **Sticker & custom emoji catalog (`stickers.list`, `stickers.import`):**
   - Lists three local/bridged sources without any third-party cloud service: (a) **Recent stickers** extracted from received and sent `m.sticker` rows in SQLite `events`, (b) **User-imported stickers & custom `:shortcode:` emoji** persisted in `<dataDir>/media/stickers.json` + `media.Store`, and (c) **Bridge-imported packs** fetched on demand from connected logins whose `NetworkAPI` implements `bridgev2.StickerImportingNetworkAPI` (`GetUserStickerPacks`, implemented by Telegram and Slack).
4. **Composer `:` emoji autocomplete (`Autocomplete.tsx`, `EmojiItem.tsx`) & `:)` emoticon replacement:**
   - Typing `:smile` (after start-of-text or whitespace, when `enableEmojiAutocomplete` is on) opens `EmojiAutocompletePicker` above the composer showing matching bundled Unicode emoji and custom workspace/imported emoji cells (`EmojiItem`), with ↑/↓/Return/Tab/Escape navigation and an `"Add :shortcode: to Custom Emoji"` footer action (`NSOpenPanel`).
   - Typing a classic ASCII emoticon followed by a space or Return (e.g. `:)` → `🙂`, `:D` → `😃`, `;)` → `😉`, `:(` → `🙁`, `<3` → `❤️`, `:P` → `😛`, `:/` → `😕`, `B)` → `😎`) replaces the emoticon in-place unless `disableEmoticonReplacement` is on (or the cursor is inside a code span / URL).
5. **Sticker picker (`StickerPicker.tsx`, `⌘⌥⇧S`) & GIF picker (`GifPicker.tsx`, `⌘⇧G`, `/gif`) with `GIFProvider` stub:**
   - `StickerPickerPopover` shows pack tabs (Recent, Imported, and bridge packs), a search filter, a 4-column 64×64 pt sticker grid, and `"Import Sticker…"` (`NSOpenPanel`). Clicking a sticker sends it via `message.sendSticker`.
   - `GIFProvider` protocol + `StubGIFProvider` (`isAvailable == false`, zero outbound requests per Spec §3 and §7 4.7). `GIFPickerPopover` opens from the composer toolbar, `+` menu (`Add GIF…`), `⌘⇧G`, or `/gif <query>` (replacing the temporary `gifNotice` banner with the real popover pre-filled with `<query>`). It shows the search field, an honest offline notice explaining that online GIF search is disabled for privacy, a grid of recent/local GIFs from `media.Store`, and `"Choose GIF from Mac…"` (`NSOpenPanel` for `.gif` and `.mp4`). When `Automatically send GIFs after selection` is on, picking a GIF calls `message.sendGIF` immediately; when off, it stages a pending GIF draft in the composer so the user can add an optional caption and press Return.
6. **Settings, `+` menu items (`Emoji.tsx`), hotkeys, and borderless sticker / looping GIF bubbles:**
   - Adds the three `setting:general` rows to `MessagesSettingsPane` (`Enable emoji autocomplete`, `Disable automatic replacement of emoticons with emojis`, `Automatically send GIFs after selection`), the `Add Emoji…`, `Add GIF…`, and `Add Sticker…` items to the composer `+` menu, `Send GIF` (`⌘⇧G`) and `Send Sticker` (`⌘⌥⇧S`) to the `Message` menu, and borderless sticker (`m.sticker` up to 160×160 pt) + looping `"GIF"` badge rendering in `MessageBubble` with light and dark PNG snapshot tests.

### Surprises found in the pinned `bridgev2` and bridge sources
1. **Google Messages and Slack do not support outgoing `m.sticker` (`event.CapMsgSticker`):**
   - In `go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/connector/capabilities.go:116-195` and `go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/capabilities.go:140-175`, `event.CapMsgGIF` is present (`image/gif` full), while `event.CapMsgSticker` is completely absent. Sending an `m.sticker` event to a room whose `RoomCapabilities.File` lacks `event.CapMsgSticker` fails capability validation in `bridgev2`. Our `room.features` reports `sticker.supported = false` for Google Messages and Slack so the UI disables `Add Sticker…` and `⌘⌥⇧S` with `"Send Sticker (Unavailable for Slack)"` / `"Send Sticker (Unavailable for Google Messages)"`.
2. **Slack implements `StickerImportingNetworkAPI` for custom workspace emoji, even though it doesn't send `m.sticker`:**
   - `go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/emoji.go:36` declares `var _ bridgev2.StickerImportingNetworkAPI = (*SlackClient)(nil)` and returns custom workspace emoji packs marked with `Usage: []event.ImagePackUsage{event.ImagePackUsageEmoticon, event.ImagePackUsageSticker}` (`emoji.go:55`). That means `GetUserStickerPacks` gives us Slack's `:custom_emoji:` shortcodes for the composer `:` autocomplete picker!
3. **Telegram implements `StickerImportingNetworkAPI` and reuses native document IDs via `fi.mau.bridged_sticker`:**
   - `go.mau.fi/mautrix-telegram@v0.2609.0/pkg/connector/imagepack.go:480` implements `GetUserStickerPacks` (fetching `MessagesGetAllStickers` and `MessagesGetEmojiStickers`). Each `PackImage` includes `BridgedSticker` (`Network: "telegram"`, `PackURL: "https://t.me/addstickers/" + shortName`, `ID: document.ID` at `imagepack.go:500-523`), and `imagepack.go:742` checks `Info.BridgedSticker` on outgoing stickers so Telegram can send the native sticker document directly. Preserving `fi.mau.bridged_sticker` (`event.BridgedSticker` in `maunium.net/go/mautrix@v0.31.0/event/imagepack.go:29`) in `stickers.list` and `message.sendSticker` keeps native Telegram sticker fidelity.
4. **GIFs are not a separate Matrix event type — they are `m.video` or `m.image` with `info["fi.mau.gif"] = true`:**
   - In `maunium.net/go/mautrix@v0.31.0/event/message.go:344`, `FileInfo` has `MauGIF bool` (`json:"fi.mau.gif,omitzero"`), and `event/capabilities.go:203` defines `CapMsgGIF = "fi.mau.gif"`. WhatsApp (`capabilities.go:137-145`, `tomatrix.go:579`), Signal (`capabilities.go:135-142`, `handlematrix.go:205,317`), Telegram (`capabilities.go:137-145`, `tomatrix.go:833`), Google Messages (`capabilities.go:119,146,187`), and Slack (`capabilities.go:156-163`) all key off `Info.MauGIF == true` and `caps.File[event.CapMsgGIF]`. Notably, WhatsApp only supports `image/gif` when `ffmpeg` is installed on the host (`supportedIfFFmpeg()` at `capabilities.go:62-67`), whereas `video/mp4` is always `CapLevelFullySupported` (`capabilities.go:139`).

### Decisions for the owner to check
- **`GIFProvider` is a strict local stub (no Tenor / Giphy / Klipy key or network calls):** Per Spec §3 (Out-of-Scope #7: *"No Giphy / Tenor / Klipy GIF search integration (`GifPicker.tsx` becomes a stub or is hidden; local GIF file send still works)"*) and §7 4.7 (*"Stub `GIFProvider` protocol; no third-party GIF API calls in Iteration 1"*), `StubGIFProvider` makes zero network calls. The GIF picker lets the user pick any local `.gif` or `.mp4` from their Mac (`NSOpenPanel`) or re-send recent GIFs already in `media.Store`, and shows a clear privacy note explaining why online GIF search is off.
- **No SQLite schema version bump required (avoids colliding with 4.5b):** Received and sent stickers are already stored in `events` with `type = 'm.sticker'` and JSON `content`. User-imported stickers/custom emoji and cached bridge sticker pack manifests live in `<dataDir>/media/stickers.json` alongside their content-addressed blobs in `media.Store`. This keeps `store.SchemaVersion = 8` untouched and avoids any migration conflict with 4.5b.
- **Parallel coexistence with 4.5b:** Tasks 2, 8, and 10 note exact touchpoints with `4.5b Task 1` (`room.features`), `4.5b Task 2` (`message.sendFile`), `4.5b Task 6` (`MediaAttachmentView`), and `4.5b Task 7` (`ComposerAttachment`) so either milestone can merge first cleanly.

### Main risks the tests target
- **Sticker capability rejection on Google Messages & Slack:** Sending `m.sticker` where `CapMsgSticker` is unsupported must be caught by `actions.SendSticker` (`ErrUnsupportedFeature`) and disabled in the UI before the user clicks send.
- **Emoticon replacement false positives:** `:)` inside a URL (`https://example.com/:)`) or inline code (`` `:)` ``) or mid-word (`http://foo:80`) must **not** turn into an emoji. Replacement only fires on whitespace/start-of-line boundaries followed by space or Return.
- **Undo-send hold window for stickers and GIFs:** Both `message.sendSticker` and `message.sendGIF` must honour `hold_ms` in `outbox` and `actions.Retry` (`actions.go:927`) just like `message.send` and `message.sendVoice`, so pressing Undo cancels the sticker/GIF before it reaches the bridge.

---

## Per-Network Sticker & GIF Capability Matrix (Verified in `~/go/pkg/mod`)

All facts below are verified against the pinned Go modules in `~/go/pkg/mod` (exact `grep` commands in the Appendix):

| Network | Pinned Module | Outgoing Sticker (`event.CapMsgSticker`) | Outgoing GIF (`event.CapMsgGIF`) | Sticker/Emoji Pack Import (`StickerImportingNetworkAPI`) | Source Citation (`~/go/pkg/mod`) |
|---|---|---|---|---|---|
| **WhatsApp** | `go.mau.fi/mautrix-whatsapp@v0.2609.0` | **Supported:** `image/webp` (full), `image/png` (partial), `image/jpeg` (partial), `video/lottie+json` (partial); `Caption: CapLevelDropped`, `MaxSize: 2 GiB` | **Supported:** `video/mp4` (full), `image/gif` (`supportedIfFFmpeg()`); `Caption: CapLevelFullySupported`, `MaxCaptionLength: 65536` | Not implemented | `pkg/connector/capabilities.go:126-145`, `handlematrix.go:530`, `tomatrix.go:579,797` |
| **Signal** | `go.mau.fi/mautrix-signal@v0.2609.0` | **Supported:** `image/png` (full), `image/apng` (full), `image/webp` (partial — static on Signal), `image/gif` (`supportedIfFFmpeg()`); `Caption: CapLevelDropped`, `MaxSize: 100 MiB` | **Supported:** `image/gif` (full), `video/mp4` (full); `Caption: CapLevelFullySupported`, `MaxCaptionLength: 2000` | Not implemented | `pkg/connector/capabilities.go:115-143`, `handlematrix.go:196,205,317,356,376`, `signal.go:634,648` |
| **Telegram** | `go.mau.fi/mautrix-telegram@v0.2609.0` | **Supported:** `image/webp` (full), `video/lottie+json` (full), `video/webm` (full), `image/jpeg` (partial), `image/png` (partial); `Caption: CapLevelUnsupported` | **Supported:** `video/mp4` (full), `image/gif` (partial); `Caption: CapLevelFullySupported` | **Implemented:** `GetUserStickerPacks` returns saved sticker sets + emoji stickers with `BridgedSticker` metadata | `pkg/connector/capabilities.go:137-155`, `imagepack.go:480-525,742`, `tomatrix.go:739,833` |
| **Google Messages** | `go.mau.fi/mautrix-gmessages@v0.2609.0` | **Unsupported** (`CapMsgSticker` absent from `File` map) | **Supported:** `image/gif` (full), `MaxSize: 100 MiB` (captions dropped on RCS, supported on MMS) | Not implemented | `pkg/connector/capabilities.go:119-121,146-149,187-191` |
| **Slack** | `go.mau.fi/mautrix-slack@v0.2609.1` | **Unsupported** (`CapMsgSticker` absent from `File` map) | **Supported:** `image/gif` (full), `Caption: CapLevelFullySupported`, `MaxCaptionLength: 40000` | **Implemented:** `GetUserStickerPacks` returns custom workspace emoji packs (`Usage: [emoticon, sticker]`) | `pkg/connector/capabilities.go:156-163`, `emoji.go:36-74` |

---

## Global Constraints

1. **Bazel-only builds, tests, and git operations:** Never invoke `go test`, `swift test`, or raw `git commit`/`git push`. Use `bazel test //apps/desktop/courier/...` and `bazel run //tools/git:commit -- --agent <you> ...`.
2. **macOS 14.0 deployment target (`apps/desktop/courier/app/BUILD:136`):** Only use APIs available in macOS 14.0 (`AppKit`: `NSTextView`, `NSImageView`, `NSOpenPanel`, `NSWorkspace`; `ImageIO`: `CGImageSourceCreateWithData`, `CGImageSourceCopyPropertiesAtIndex`; `UniformTypeIdentifiers`: `UTType.png`, `UTType.gif`, `UTType.webP`, `UTType.mpeg4Movie`).
3. **Privacy & outbound connections:** Nothing leaves the Mac unless the user triggers it:
   - `StubGIFProvider` makes **zero** outbound connections.
   - Emoji autocomplete and emoticon replacement run 100% locally in memory.
   - Outbound bridge traffic occurs **only** when (a) the user sends a sticker (`message.sendSticker`) or GIF (`message.sendGIF`) to the active room's connected bridge, or (b) the engine syncs custom emoji / sticker packs from an already-authenticated Telegram or Slack bridge session (`StickerImportingNetworkAPI.GetUserStickerPacks`) and downloads a selected pack thumbnail via the bridge's own media path.
4. **View verification:** Every new or updated SwiftUI view is verified by deterministic light and dark PNG snapshot tests in `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`. There is no fake-network app mode.

---

## Review Focus

- **Capability parity with `bridgev2`:** Does `actions.Features` accurately reflect `event.CapMsgSticker` and `event.CapMsgGIF` (including WhatsApp's `video/mp4` vs `image/gif` support and Google Messages / Slack lacking `CapMsgSticker`)?
- **Composer key handling:** Does `EmojiAutocompletePicker` coexist cleanly with `@` `MentionPicker` and `/` `SlashCommandPicker` in `ComposerView` and `RichTextView` without stealing arrow/Return keys when closed?
- **Settings wiring:** Do all three `setting:general` toggles in `MessagesSettingsPane` persist via `ComposerPreferences` (`UserDefaults`) and immediately alter `ComposerModel` behaviour?

---

### Task 1: Sticker and GIF room features (`room.features`)

**Files:**
- Modify: `apps/desktop/courier/engine/internal/actions/features.go`
- Modify: `apps/desktop/courier/engine/internal/actions/features_test.go`
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Modify: `apps/desktop/courier/protocol/examples/room.features.json`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ChatFeatures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift`

**Interfaces:**
- Go (`engine/internal/actions/features.go`):
  ```go
  type MediaCapFeature struct {
      Supported        bool     `json:"supported"`
      MimeTypes        []string `json:"mime_types"`
      Captions         bool     `json:"captions"`
      MaxCaptionLength int      `json:"max_caption_length,omitempty"`
      MaxSize          int64    `json:"max_size,omitempty"`
  }
  ```
  Add `Sticker MediaCapFeature` (`json:"sticker"`) and `GIF MediaCapFeature` (`json:"gif"`) to `RoomFeatures` (coexisting with `VoiceNote VoiceNoteFeature` and, if `4.5b Task 1` has landed, `Attachments`).
- Swift (`app/Sources/CourierCore/Protocol.swift` and `ChatFeatures.swift`):
  ```swift
  public struct MediaCapFeatureWire: Codable, Equatable, Sendable {
      public var supported: Bool
      public var mimeTypes: [String]
      public var captions: Bool
      public var maxCaptionLength: Int?
      public var maxSize: Int64?
  }
  ```
  Expose `sticker: MediaCapFeatureWire` and `gif: MediaCapFeatureWire` on `RoomFeaturesResult` and `ChatFeatures` (`ChatFeatures.conservative` defaults both to `supported: false`).

**Steps:**
- [ ] Write failing unit tests in `engine/internal/actions/features_test.go` covering:
  - WhatsApp-like capabilities (`CapMsgSticker` with `image/webp` full + `Caption: CapLevelDropped`; `CapMsgGIF` with `video/mp4` full + `Caption: CapLevelFullySupported`),
  - Google Messages / Slack capabilities (`CapMsgGIF` with `image/gif` full, `CapMsgSticker` absent → `Sticker.Supported == false`),
  - `CapLevelRejected` / `CapLevelUnsupported` MIME filtering (only `CapLevelFullySupported`, `CapLevelPartialSupport`, and `CapLevelDropped` count as sendable MIME types; `MimeTypes` sorted deterministically).
- [ ] Implement `extractMediaCap(caps.File[event.CapMsgSticker])` and `extractMediaCap(caps.File[event.CapMsgGIF])` in `engine/internal/actions/features.go`.
- [ ] Update `protocol/protocol.json` and `protocol/examples/room.features.json` to include `"sticker"` and `"gif"` on `room.features`.
- [ ] Update `Protocol.swift`, `ChatFeatures.swift`, and `ChatFeaturesTests.swift` to decode `sticker` and `gif` and verify round-trip decoding against `protocol/examples/room.features.json`.
- [ ] Run `bazel test //apps/desktop/courier/engine/internal/actions:actions_test //apps/desktop/courier/protocol:protocol_test //apps/desktop/courier/app:CourierCoreTests`.

---

### Task 2: Sending stickers and GIFs in the engine (`message.sendSticker`, `message.sendGIF`)

> **Coexistence note:** Needs or parallels `4.5b Task 2` (`message.sendFile`). Both touch `actions.go`, `outbox.go`, and `rpc/messages.go`. Keep `SendSticker` and `SendGIF` in dedicated methods so merges are additive.

**Files:**
- Modify: `apps/desktop/courier/engine/internal/actions/actions.go`
- Modify: `apps/desktop/courier/engine/internal/actions/outbox.go`
- Modify: `apps/desktop/courier/engine/internal/actions/send_test.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/messages.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/messages_test.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/methods.go`
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Create: `apps/desktop/courier/protocol/examples/message.sendSticker.json`
- Create: `apps/desktop/courier/protocol/examples/message.sendGIF.json`

**Interfaces:**
- Go (`engine/internal/actions/actions.go`):
  ```go
  type BridgedStickerRef struct {
      Network string `json:"network,omitempty"`
      PackURL string `json:"pack_url,omitempty"`
      ID      string `json:"id,omitempty"`
  }

  type SendStickerReq struct {
      RoomID         string             `json:"room_id"`
      Path           string             `json:"path,omitempty"`
      MediaURL       string             `json:"media_url,omitempty"`
      Name           string             `json:"name,omitempty"`
      Emoji          string             `json:"emoji,omitempty"`
      MimeType       string             `json:"mime_type,omitempty"`
      BridgedSticker *BridgedStickerRef `json:"bridged_sticker,omitempty"`
      ReplyTo        string             `json:"reply_to,omitempty"`
      ThreadRoot     string             `json:"thread_root,omitempty"`
      HoldMillis     int                `json:"hold_ms,omitempty"`
  }

  type SendGIFReq struct {
      RoomID     string `json:"room_id"`
      Path       string `json:"path,omitempty"`
      MediaURL   string `json:"media_url,omitempty"`
      Caption    string `json:"caption,omitempty"`
      ReplyTo    string `json:"reply_to,omitempty"`
      ThreadRoot string `json:"thread_root,omitempty"`
      HoldMillis int    `json:"hold_ms,omitempty"`
  }
  ```
- JSON-RPC methods (`engine/internal/rpc/methods.go`, `protocol/protocol.json`):
  - `message.sendSticker` → `SendStickerReq` → `SendResult` (`{"event_id": "..."}`)
  - `message.sendGIF` → `SendGIFReq` → `SendResult` (`{"event_id": "..."}`)

**Steps:**
- [ ] Write failing tests in `engine/internal/actions/send_test.go` and `engine/internal/rpc/messages_test.go` covering:
  - `SendSticker` from a local `.png` / `.webp` path or existing `courier://media/...` URL: copies bytes into `media.Store`, extracts image width/height (`image.DecodeConfig` with `golang.org/x/image/webp` or PNG/GIF/JPEG stdlib decoders), populates `event.MessageEventContent{MsgType: event.MsgImage, Body: body, URL: uri, Info: &event.FileInfo{MimeType, Size, Width, Height, BridgedSticker}}`, and dispatches `event.EventSticker` (`m.sticker`) to `Room.HandleMatrixMessage`.
  - `SendSticker` returns `ErrUnsupportedFeature` when the room's `CapMsgSticker` capability is missing or rejects all sticker MIME types (e.g., Google Messages, Slack).
  - `SendGIF` from a `.gif` (`image/gif`, `MsgType: event.MsgImage`) or `.mp4` (`video/mp4`, `MsgType: event.MsgVideo`) path or existing `courier://media/...` URL: sets `Info.MauGIF = true` (`"fi.mau.gif": true`), attaches optional `Caption` (`Body` + `FileName` when caption is non-empty per Matrix caption convention), and dispatches `event.EventMessage`.
  - `SendSticker` and `SendGIF` with `HoldMillis > 0` hold the event in `outbox`, cancel cleanly on `UndoSend`, and re-dispatch `event.EventSticker` or `event.EventMessage` on `actions.Retry` (`actions.go:927`).
- [ ] Extend `pendingSend` in `engine/internal/actions/outbox.go` with `eventType event.Type` (defaulting to `event.EventMessage`, set to `event.EventSticker` for stickers) and update `actions.Retry` in `engine/internal/actions/actions.go` to check `ev.Type == event.EventSticker.Type` when reconstructing the `event.Event` for `Room.HandleMatrixMessage`.
- [ ] Implement `SendSticker` and `SendGIF` in `engine/internal/actions/actions.go`, wire `message.sendSticker` and `message.sendGIF` in `engine/internal/rpc/messages.go` and `methods.go`, and add schema + example fixtures in `protocol/protocol.json`, `protocol/examples/message.sendSticker.json`, and `protocol/examples/message.sendGIF.json`.
- [ ] Run `bazel test //apps/desktop/courier/engine/internal/actions:actions_test //apps/desktop/courier/engine/internal/rpc:rpc_test //apps/desktop/courier/protocol:protocol_test`.

---

### Task 3: Sticker and custom emoji catalog in the engine (`stickers.list`, `stickers.import`)

**Files:**
- Create: `apps/desktop/courier/engine/internal/store/stickers.go`
- Create: `apps/desktop/courier/engine/internal/store/stickers_test.go`
- Create: `apps/desktop/courier/engine/internal/actions/stickers.go`
- Create: `apps/desktop/courier/engine/internal/actions/stickers_test.go`
- Create: `apps/desktop/courier/engine/internal/rpc/stickers.go`
- Create: `apps/desktop/courier/engine/internal/rpc/stickers_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/BUILD`
- Modify: `apps/desktop/courier/engine/internal/actions/BUILD`
- Modify: `apps/desktop/courier/engine/internal/rpc/BUILD`
- Modify: `apps/desktop/courier/engine/internal/rpc/methods.go`
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Create: `apps/desktop/courier/protocol/examples/stickers.list.json`
- Create: `apps/desktop/courier/protocol/examples/stickers.import.json`

**Interfaces:**
- Go (`engine/internal/actions/stickers.go`):
  ```go
  type StickerItem struct {
      ID             string             `json:"id"`
      PackID         string             `json:"pack_id"`
      Shortcode      string             `json:"shortcode,omitempty"`
      Name           string             `json:"name"`
      Emoji          string             `json:"emoji,omitempty"`
      MediaURL       string             `json:"media_url"`
      MimeType       string             `json:"mime_type"`
      Width          int                `json:"width,omitempty"`
      Height         int                `json:"height,omitempty"`
      Usage          []string           `json:"usage"` // ["sticker"], ["emoticon"], or both
      BridgedSticker *BridgedStickerRef `json:"bridged_sticker,omitempty"`
  }

  type StickerPack struct {
      ID       string        `json:"id"`
      Title    string        `json:"title"`
      Source   string        `json:"source"` // "recent" | "imported" | "bridge"
      Network  string        `json:"network,omitempty"`
      Items    []StickerItem `json:"items"`
  }

  type ListStickersResult struct {
      Packs      []StickerPack `json:"packs"`
      RecentGIFs []StickerItem `json:"recent_gifs"`
  }

  type ImportStickerReq struct {
      Path      string   `json:"path"`
      Shortcode string   `json:"shortcode,omitempty"`
      Name      string   `json:"name,omitempty"`
      Emoji     string   `json:"emoji,omitempty"`
      Usage     []string `json:"usage,omitempty"` // defaults to ["sticker"] or ["emoticon","sticker"] if Shortcode != ""
  }
  ```
- JSON-RPC methods:
  - `stickers.list` (`{"refresh_bridge_packs": false}`) → `ListStickersResult`
  - `stickers.import` (`ImportStickerReq`) → `StickerItem`

**Steps:**
- [ ] Write failing unit tests in `engine/internal/store/stickers_test.go` for querying recent unique `m.sticker` items and recent `fi.mau.gif` items from the `events` table (`WHERE type = 'm.sticker' AND redacted = 0` and `WHERE type = 'm.room.message' AND redacted = 0 AND json_extract(content, '$.info."fi.mau.gif"') = 1`, ordered by `ts DESC`, deduplicated by `url`, capped at 40).
- [ ] Implement `ListRecentStickers(limit int)` and `ListRecentGIFs(limit int)` in `engine/internal/store/stickers.go` and add `stickers.go` / `stickers_test.go` to `engine/internal/store/BUILD`.
- [ ] Write failing unit tests in `engine/internal/actions/stickers_test.go` covering:
  - `ImportSticker`: validates the file extension/MIME (`.png`, `.webp`, `.gif`, `.apng`, `.jpg`), writes it into `media.Store`, normalizes `Shortcode` (stripping surrounding `:`), persists the entry to `<dataDir>/media/stickers.json`, and returns `StickerItem`.
  - `ListStickers`: returns the `"recent"` pack from `store.ListRecentStickers`, the `"imported"` pack from `stickers.json`, any bridge packs from connected logins whose `Client` implements `bridgev2.StickerImportingNetworkAPI` (`GetUserStickerPacks`, tested with a fake `StickerImportingNetworkAPI` returning both Telegram-style stickers with `BridgedSticker` and Slack-style custom emoji with `ImagePackUsageEmoticon`), plus `RecentGIFs` from `store.ListRecentGIFs`.
- [ ] Implement `engine/internal/actions/stickers.go`, wire `stickers.list` and `stickers.import` in `engine/internal/rpc/stickers.go` and `methods.go`, update `BUILD` files and `protocol/protocol.json`, and create `protocol/examples/stickers.list.json` and `protocol/examples/stickers.import.json`.
- [ ] Run `bazel test //apps/desktop/courier/engine/internal/store:store_test //apps/desktop/courier/engine/internal/actions:actions_test //apps/desktop/courier/engine/internal/rpc:rpc_test //apps/desktop/courier/protocol:protocol_test`.

---

### Task 4: Composer preferences and `General → Composing` toggles

**Files:**
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerPreferences.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ComposerPreferencesTests.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessagesSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`

**Interfaces:**
- Swift (`app/Sources/CourierCore/ComposerPreferences.swift`):
  ```swift
  @Published public var enableEmojiAutocomplete: Bool   // default: true  ("courier.composer.enableEmojiAutocomplete")
  @Published public var disableEmoticonReplacement: Bool // default: false ("courier.composer.disableEmoticonReplacement")
  @Published public var autoSendGIFs: Bool               // default: false ("courier.composer.autoSendGIFs")
  ```
- Inventory settings rows in `MessagesSettingsPane.swift` (`General → Composing` section):
  - `setting:general	Enable emoji autocomplete`
  - `setting:general	Disable automatic replacement of emoticons with emojis`
  - `setting:general	Automatically send GIFs after selection`

**Steps:**
- [ ] Write failing unit tests in `ComposerPreferencesTests.swift` verifying default values (`enableEmojiAutocomplete == true`, `disableEmoticonReplacement == false`, `autoSendGIFs == false`) and `UserDefaults` persistence across re-instantiation.
- [ ] Add the three `@Published` properties and `UserDefaults` keys to `ComposerPreferences.swift`.
- [ ] Add localization keys in `app/Resources/en.lproj/Localizable.strings` and add the three `Toggle` controls inside the `"Composing"` section of `MessagesSettingsPane.swift` with accessibility identifiers `"settings.composing.enableEmojiAutocomplete"`, `"settings.composing.disableEmoticonReplacement"`, and `"settings.composing.autoSendGIFs"`.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

### Task 5: Emoji catalog, `:shortcode:` autocomplete, emoticon replacement, and `/gif` in `ComposerModel`

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/EmojiCatalog.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/EmojiCatalogTests.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerModel.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ComposerModelTests.swift`

**Interfaces:**
- Swift (`app/Sources/CourierCore/EmojiCatalog.swift`):
  ```swift
  public struct EmojiCandidate: Identifiable, Equatable, Sendable {
      public var id: String          // shortcode without colons, e.g. "smile"
      public var shortcode: String   // "smile"
      public var glyph: String?      // "😄" for Unicode emoji; nil for image-only custom emoji
      public var mediaURL: String?   // courier://media/... or mxc:// for custom emoji
      public var isCustom: Bool
      public var keywords: [String]
  }

  public struct EmojiCatalog: Sendable {
      public static let shared: EmojiCatalog
      public func search(_ query: String, custom: [EmojiCandidate], limit: Int) -> [EmojiCandidate]
      public static func replaceTrailingEmoticon(in text: String) -> String?
  }
  ```
- Swift (`app/Sources/CourierCore/ComposerModel.swift`):
  - `@Published public private(set) var emojiQuery: String?`
  - `@Published public private(set) var emojiCandidates: [EmojiCandidate]`
  - `@Published public var selectedEmojiIndex: Int`
  - `@Published public var isEmojiPickerPresented: Bool`
  - `@Published public var isStickerPickerPresented: Bool`
  - `@Published public var isGIFPickerPresented: Bool`
  - `@Published public var gifSearchQuery: String`
  - `public func moveEmojiSelection(_ delta: Int)`
  - `public func pickEmoji(_ candidate: EmojiCandidate)`
  - `public func dismissEmojiAutocomplete()`

**Steps:**
- [ ] Write failing tests in `EmojiCatalogTests.swift` and `ComposerModelTests.swift` covering:
  - `EmojiCatalog.search("smi")` returns prefix matches (`smile`, `smiley`, `smirk`) ahead of substring/keyword matches, and merges custom emoji (`isCustom: true`) matching the query.
  - Typing `"hello :smi"` in `ComposerModel` when `preferences.enableEmojiAutocomplete == true` sets `emojiQuery = "smi"` and populates `emojiCandidates`; when `preferences.enableEmojiAutocomplete == false`, `emojiQuery` stays `nil`.
  - `pickEmoji` replaces `:smi` with `"😄 "` (or `:custom_code: ` when `glyph == nil`) and clears `emojiQuery`.
  - Typing `":) "` or `":-D\n"` when `preferences.disableEmoticonReplacement == false` replaces the emoticon with `"🙂 "` / `"😃\n"`; typing `"https://example.com/:) "` or `` "`:) " `` or setting `preferences.disableEmoticonReplacement = true` leaves the text untouched.
  - Executing `/gif` or `/gif cats` sets `isGIFPickerPresented = true` and `gifSearchQuery = "cats"` (and clears the composer text).
- [ ] Implement `EmojiCatalog.swift` with the bundled Unicode shortcode dictionary + `replaceTrailingEmoticon(in:)` table (`:)`, `:-)`, `:D`, `:-D`, `;)`, `;-)`, `:(`, `:-(`, `:'(`, `:P`, `:-P`, `:p`, `<3`, `</3`, `:/`, `:-/`, `:O`, `:-O`, `B)`, `B-)`, `:*`, `>_<`, `o_O`).
- [ ] Update `ComposerModel.swift` (`recomputeAutocomplete` and `handleTextEdit`) to detect `:shortcode` tokens (requiring at least 2 characters after `:` or an explicit `openEmojiAutocomplete()` trigger), apply `EmojiCatalog.replaceTrailingEmoticon` on space/newline when `!preferences.disableEmoticonReplacement`, and wire `/gif` to open `isGIFPickerPresented` with `gifSearchQuery`.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

### Task 6: Composer `:` emoji autocomplete popover (`Autocomplete.tsx`, `EmojiItem.tsx`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/EmojiAutocompletePicker.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/RichTextView.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`

**Interfaces:**
- Swift (`app/Sources/Courier/EmojiAutocompletePicker.swift`):
  ```swift
  public struct EmojiItemRow: View {
      public let candidate: EmojiCandidate
      public let isSelected: Bool
      public let thumbnailLoader: ThumbnailLoader?
  }

  public struct EmojiAutocompletePicker: View {
      public let query: String
      public let candidates: [EmojiCandidate]
      public let selectedIndex: Int
      public let thumbnailLoader: ThumbnailLoader?
      public let onSelect: (EmojiCandidate) -> Void
      public let onAddCustomEmoji: (String) -> Void
  }
  ```

**Steps:**
- [ ] Build `EmojiItemRow` (`EmojiItem.tsx`) and `EmojiAutocompletePicker` (`Autocomplete.tsx`) in `EmojiAutocompletePicker.swift`:
  - Renders up to 8 matching `EmojiCandidate` rows with the Unicode glyph (or 20×20 pt custom emoji image via `ThumbnailLoader`) and `:shortcode:`, highlighting `selectedIndex`.
  - Includes the footer button `"Add :%@: to Custom Emoji"` (`String(format: L10n.tr("composer.emoji.addCustom"), query)`) when `query` is non-empty, which opens `NSOpenPanel` (`allowedContentTypes: [.png, .webP, .gif]`) and imports the chosen image via `stickers.import` with `shortcode: query` and `usage: ["emoticon", "sticker"]`.
- [ ] Update `RichTextView.swift` (`Coordinator.textView(_:doCommandBy:)`) and `ComposerView.swift` so ↑, ↓, Return, Tab, and Escape navigate/accept/dismiss `EmojiAutocompletePicker` whenever `composer.emojiQuery != nil`, matching the existing `MentionPicker` and `SlashCommandPicker` key routing.
- [ ] Mount `EmojiAutocompletePicker` above the text field in `ComposerView.swift` alongside `MentionPicker` and `SlashCommandPicker`.
- [ ] Run `bazel build //apps/desktop/courier/app/...` and `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

### Task 7: Sticker picker popover and sending (`StickerPicker.tsx`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/StickerPickerPopover.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/EngineMessageSender.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerModel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/Fakes.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ProtocolConformanceTests.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`

**Interfaces:**
- Swift (`Protocol.swift` & `ComposerModel.swift`):
  - Wire structs `StickerItemWire`, `StickerPackWire`, `StickersListParams`, `StickersListResult`, `StickersImportParams`, `MessageSendStickerParams`.
  - Extend `MessageSending` protocol with:
    ```swift
    func listStickers(refreshBridgePacks: Bool) async throws -> StickersListResult
    func importSticker(_ params: StickersImportParams) async throws -> StickerItemWire
    func sendSticker(_ params: MessageSendStickerParams) async throws -> String
    ```
  - `ComposerModel.loadStickers(refresh: Bool = false) async`, `ComposerModel.importSticker(from url: URL, shortcode: String? = nil) async`, `ComposerModel.sendSticker(_ item: StickerItemWire) async`.

**Steps:**
- [ ] Add `StickersListResult`, `StickerPackWire`, `StickerItemWire`, `StickersImportParams`, and `MessageSendStickerParams` to `Protocol.swift`, implement the RPC calls in `EngineMessageSender.swift`, and add test doubles in `Fakes.swift` + schema checks in `ProtocolConformanceTests.swift`.
- [ ] Add unit tests in `ComposerModelTests.swift` verifying `loadStickers`, `importSticker`, and `sendSticker` (including passing `holdMillis` from `preferences.undoSendHoldMillis` and registering the pending undoable send).
- [ ] Create `StickerPickerPopover.swift` (`StickerPicker.tsx`):
  - Pack selector tabs at top (`Recent`, `Imported`, and bridge packs with network badge), search field (`"Search stickers"`), 4-column `LazyVGrid` of 64×64 pt sticker cells (rendered via `ThumbnailLoader` with hover scale/highlight and accessibility label `item.name`), empty-state view when no stickers exist yet, and footer buttons `"Import Sticker…"` (`NSOpenPanel` for `.png`, `.webp`, `.gif`) and `"Sync Packs"`.
- [ ] Attach `.popover(isPresented: $composer.isStickerPickerPresented)` to `ComposerView.swift`.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

### Task 8: `GIFProvider` stub and GIF picker popover (`GifPicker.tsx`)

> **Coexistence note:** When `preferences.autoSendGIFs == false`, picking a GIF stages it on `ComposerModel` (`pendingGIF: StickerItemWire?`) so pressing Return in `ComposerModel.send()` sends it via `message.sendGIF` with `text` as the caption. If `4.5b Task 7` (`ComposerAttachment`) is already merged, `pendingGIF` renders alongside the composer draft strip.

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/GIFProvider.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/GIFPickerPopover.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/GIFProviderTests.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/EngineMessageSender.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerModel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/Fakes.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ProtocolConformanceTests.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`

**Interfaces:**
- Swift (`app/Sources/CourierCore/GIFProvider.swift`):
  ```swift
  public struct GIFCandidate: Identifiable, Equatable, Sendable {
      public var id: String
      public var title: String
      public var mediaURL: String
      public var mimeType: String
      public var width: Int?
      public var height: Int?
  }

  public protocol GIFProvider: Sendable {
      var isAvailable: Bool { get }
      func trending() async throws -> [GIFCandidate]
      func search(_ query: String) async throws -> [GIFCandidate]
  }

  public struct StubGIFProvider: GIFProvider {
      public init() {}
      public var isAvailable: Bool { false }
      public func trending() async throws -> [GIFCandidate] { [] }
      public func search(_ query: String) async throws -> [GIFCandidate] { [] }
  }
  ```
- Swift (`Protocol.swift` & `EngineMessageSender.swift`):
  - `MessageSendGIFParams` and `func sendGIF(_ params: MessageSendGIFParams) async throws -> String` on `MessageSending`.

**Steps:**
- [ ] Write failing unit tests in `GIFProviderTests.swift` and `ComposerModelTests.swift` verifying:
  - `StubGIFProvider().isAvailable == false` and both `trending()` and `search("cats")` return `[]` immediately with zero I/O.
  - Selecting a GIF in `ComposerModel.selectGIF(_:)` when `preferences.autoSendGIFs == true` calls `sender.sendGIF` immediately and closes the popover.
  - Selecting a GIF when `preferences.autoSendGIFs == false` sets `composer.pendingGIF`, closes the popover, and lets the user type a caption and press Return (`composer.send()`) to invoke `sender.sendGIF(caption: text)`.
- [ ] Implement `GIFProvider.swift`, add `MessageSendGIFParams` to `Protocol.swift` and `EngineMessageSender.swift`, and wire `selectGIF`, `sendGIFFile(url:)`, and `pendingGIF` in `ComposerModel.swift`.
- [ ] Create `GIFPickerPopover.swift` (`GifPicker.tsx`):
  - Search field bound to `$composer.gifSearchQuery` (pre-filled when triggered via `/gif <query>`).
  - Honest offline stub banner when `!gifProvider.isAvailable`: `"Online GIF search is disabled so nothing leaves your Mac. Choose a GIF file or pick a recent GIF below."`
  - Grid of recent local GIFs (`recentGIFs` from `stickers.list`, filtered by `gifSearchQuery` on name) plus a prominent `"Choose GIF from Mac…"` button (`NSOpenPanel` with `allowedContentTypes: [.gif, .mpeg4Movie]`).
  - Pending GIF preview pill in `ComposerView.swift` (with a remove `×` button) when `composer.pendingGIF != nil`.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

### Task 9: Composer `+` menu items (`Emoji.tsx`) and `Message` menu hotkeys (`⌘⇧G`, `⌘⌥⇧S`)

**Files:**
- Modify: `apps/desktop/courier/app/Sources/CourierCore/CommandSet.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/CommandSetTests.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationCommands.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ConversationWiringTests.swift`
- Modify: `apps/desktop/courier/app/Resources/en.lproj/Localizable.strings`

**Interfaces:**
- Inventory rows covered:
  - `component	Emoji.tsx` (composer `+` menu media/emoji items: `Add Emoji…`, `Add GIF…`, `Add Sticker…`)
  - `hotkey	Message: Send GIF` (`⌘⇧G` in `ConversationCommands` / `CommandSet.id == "message.sendGIF"`)
  - `hotkey	Message: Send Sticker` (`⌘⌥⇧S` in `ConversationCommands` / `CommandSet.id == "message.sendSticker"`)

**Steps:**
- [ ] Write failing tests in `CommandSetTests.swift` and `ConversationWiringTests.swift` asserting:
  - `CommandSet` includes `message.sendGIF` (`key: "g"`, `modifiers: [.command, .shift]`) and `message.sendSticker` (`key: "s"`, `modifiers: [.command, .option, .shift]`), both falling under `.message` category.
  - When `chatFeatures.sticker.supported == false`, `canSendSticker` is `false` and the menu label formats with `L10n.featureUnavailable("Send Sticker", network: networkName)` (`"%1$@ (Unavailable for %2$@)"`).
  - When `chatFeatures.gif.supported == false`, `canSendGIF` is `false`.
- [ ] Add `sendGIF` and `sendSticker` actions to `ConversationCommandActions`, `ConversationCommands.swift` (`CommandMenu("Message")`), and `MainWindow.swift` (opening `composer.isGIFPickerPresented = true` and `composer.isStickerPickerPresented = true`).
- [ ] Update `ComposerView.plusMenu` (`ComposerView.swift:262`, corresponding to `component	Emoji.tsx`) to include a top section with:
  - `Add Emoji…` (inserts `:` or opens `NSApp.orderFrontCharacterPalette(nil)` + emoji autocomplete),
  - `Add GIF…` (`⌘⇧G`, disabled with `"%1$s (Unavailable for %2$s)"` when `!features.gif.supported`),
  - `Add Sticker…` (`⌘⌥⇧S`, disabled with `"%1$s (Unavailable for %2$s)"` when `!features.sticker.supported`),
  plus toolbar icon buttons on the trailing side of `ComposerView` for Sticker and GIF pickers.
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests`.

---

### Task 10: Sticker and GIF timeline rendering and light/dark PNG snapshot tests

> **Coexistence note:** Parallels `4.5b Task 6` (`MediaAttachmentView`). Keep sticker (`m.sticker`) and GIF (`fi.mau.gif`) rendering self-contained in `MessageBubble.swift` and `Timeline.swift` so both milestones merge cleanly.

**Files:**
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Timeline.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/MessageFixtures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/MessagePresentationTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/Fixtures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- Swift (`app/Sources/CourierCore/Timeline.swift`):
  ```swift
  public struct StickerAttachment: Equatable, Sendable {
      public var mediaURL: String
      public var name: String
      public var emoji: String?
      public var mimeType: String?
      public var width: Int?
      public var height: Int?
  }

  public struct GIFAttachment: Equatable, Sendable {
      public var mediaURL: String
      public var caption: String?
      public var mimeType: String?
      public var width: Int?
      public var height: Int?
  }
  ```
  Exposed on `MessageRow` (`sticker: StickerAttachment?`, `gif: GIFAttachment?`) decoded from `type == "m.sticker"` and `content.info["fi.mau.gif"] == true`.

**Steps:**
- [ ] Write failing unit tests in `MessagePresentationTests.swift` verifying that:
  - An event with `type == "m.sticker"` produces `row.sticker != nil` and suppresses the coloured text bubble background while keeping reactions, timestamp, and reply header.
  - An event with `type == "m.room.message"` and `info["fi.mau.gif"] == true` produces `row.gif != nil` with optional `caption`.
- [ ] Implement `StickerAttachment` and `GIFAttachment` extraction in `Timeline.swift` and render them in `MessageBubble.swift`:
  - **Stickers:** borderless container (no bubble background tint), constrained up to `160×160 pt` preserving aspect ratio, using an AppKit `NSImageView` wrapper (`animates = true` for animated GIF/APNG/WebP) with fallback emoji/label badge while loading.
  - **GIFs:** rounded `12 pt` media frame with a top-leading `"GIF"` pill badge, auto-looping inline, with optional caption rendered below the frame.
- [ ] Add light and dark PNG snapshot tests in `app/Tests/CourierViewTests/ViewSnapshotTests.swift` (using `assertLightAndDarkSnapshot`) for:
  1. `EmojiAutocompletePicker` (showing Unicode + custom emoji rows and the `"Add :party_parrot: to Custom Emoji"` footer),
  2. `StickerPickerPopover` (showing pack tabs, 4-column sticker grid, and `"Import Sticker…"` button),
  3. `GIFPickerPopover` (showing the search query, offline privacy notice, recent GIF tiles, and `"Choose GIF from Mac…"` button),
  4. `MessageBubble` with a borderless `m.sticker` item and a looping `fi.mau.gif` item,
  5. `MessagesSettingsPane` showing the three `Composing` toggles (`Enable emoji autocomplete`, `Disable automatic replacement of emoticons with emojis`, `Automatically send GIFs after selection`).
- [ ] Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests`.

---

### Task 11: Final checks and acceptance list update

**Files:**
- Modify: `apps/desktop/courier/docs/m4-acceptance.md`

**Steps:**
- [ ] Update `apps/desktop/courier/docs/m4-acceptance.md`:
  - Move the 10 inventory rows from `### Carried to later parts` (`m4-acceptance.md:957-1002`) and the composer `:` / emoticon / sticker / GIF item (`m4-acceptance.md:590`) into the verified milestone tables with concrete evidence pointers (`EmojiAutocompletePicker.swift`, `StickerPickerPopover.swift`, `GIFPickerPopover.swift`, `ComposerPreferences.swift`, `MessagesSettingsPane.swift`, `ConversationCommands.swift`, `actions/stickers.go`, `ViewSnapshotTests.swift`).
- [ ] Run the full Courier test suite and linter checks:
  ```bash
  bazel test //apps/desktop/courier/...
  ```
- [ ] Verify the working tree has no untracked build artefacts or stray files:
  ```bash
  git status --ignored
  ```

---

### Task 12: The owner's by-hand day

**Goal:** Live end-to-end verification by the owner with real accounts on macOS.

**Steps:**
- [ ] Launch Courier (`bazel run --config=macos-app //apps/desktop/courier/app:CourierApp`).
- [ ] **Settings check (`Settings → Messages → Composing`):**
  - Confirm `Enable emoji autocomplete` is ON, `Disable automatic replacement of emoticons with emojis` is OFF, and `Automatically send GIFs after selection` is OFF by default.
- [ ] **Emoji autocomplete & emoticon replacement:**
  - In any chat composer, type `:smi` → confirm the `:` autocomplete popover appears above the composer; use `↓` and `Return` to insert `😄`.
  - Type `:party_blob` → click `"Add :party_blob: to Custom Emoji"`, pick a local PNG, then type `:party_b` and confirm the custom emoji appears in the autocomplete list.
  - Type `hello :) ` (with trailing space) → confirm `:)` turns into `🙂 `. Toggle `Disable automatic replacement of emoticons with emojis` ON in Settings and verify `:)` stays literal.
- [ ] **GIF picker & `/gif` slash command:**
  - Press `⌘⇧G` (or type `/gif celebration` and press Return) → confirm the GIF picker popover opens with `"celebration"` pre-filled and displays the privacy notice (`StubGIFProvider`, zero network activity in Little Snitch / Network tab).
  - Click `"Choose GIF from Mac…"`, select a `.gif` or `.mp4` file → with `Automatically send GIFs after selection` OFF, confirm it attaches as a draft in the composer; add a caption and press Return → confirm it arrives on the remote client as a looping GIF with caption.
  - Toggle `Automatically send GIFs after selection` ON in Settings, pick the GIF from Recent GIFs in the popover, and confirm it sends immediately (with the undo-send countdown still cancellable).
- [ ] **Sticker picker across networks:**
  - In a **Telegram**, **WhatsApp**, or **Signal** chat, press `⌘⌥⇧S` (or `+ → Add Sticker…`), import or pick a sticker (or sync Telegram sticker packs), click it, and confirm it renders borderlessly in Courier's timeline and arrives as a native sticker on the phone.
  - Switch to a **Google Messages** or **Slack** chat → open the `+` menu and `Message` menu and confirm `Add Sticker…` / `Send Sticker` is disabled with `"Send Sticker (Unavailable for Google Messages)"` / `"Send Sticker (Unavailable for Slack)"`.

---

## Ledger Coverage (10 / 10 inventory rows from `ledger.tsv`)

Every row listed in the `4.5c` scope section of `docs/superpowers/plans/2026-10-25-courier-m4-5b-media.md` and `apps/desktop/courier/docs/m4-acceptance.md` is covered by the tasks above:

| `anchor` | `item` | Task(s) |
|---|---|---|
| `component` | `Autocomplete.tsx` | Task 5, Task 6, Task 10 |
| `component` | `Emoji.tsx` | Task 9, Task 10 |
| `component` | `EmojiItem.tsx` | Task 6, Task 10 |
| `component` | `GifPicker.tsx` | Task 2, Task 8, Task 10 |
| `component` | `StickerPicker.tsx` | Task 2, Task 3, Task 7, Task 10 |
| `hotkey` | `Message: Send GIF` | Task 9 |
| `hotkey` | `Message: Send Sticker` | Task 9 |
| `setting:general` | `Automatically send GIFs after selection` | Task 4, Task 8, Task 10 |
| `setting:general` | `Disable automatic replacement of emoticons with emojis` | Task 4, Task 5, Task 10 |
| `setting:general` | `Enable emoji autocomplete` | Task 4, Task 5, Task 6, Task 10 |

Plus `/gif` slash command wiring (`4.5b` line 814 → Task 5, Task 8) and the `m4-acceptance.md:590` composer checklist item (Task 5, Task 6, Task 7, Task 8, Task 11).

---

## Appendix: Mechanical Verification Commands

### 1. Pinned `~/go/pkg/mod` bridge capability and sticker/GIF greps

```bash
# mautrix v0.31.0 sticker & GIF capability constants, FileInfo.MauGIF, BridgedSticker, and StickerImportingNetworkAPI
grep -n "EventSticker" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/type.go
grep -n "CapMsgGIF\|CapMsgSticker" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/capabilities.go
grep -n "MauGIF" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/message.go
grep -n "BridgedSticker" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/imagepack.go
grep -n "StickerImportingNetworkAPI\|GetUserStickerPacks" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/bridgev2/networkinterface.go

# WhatsApp v0.2609.0
grep -n "CapMsgSticker\|CapMsgGIF\|supportedIfFFmpeg" ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/connector/capabilities.go
grep -n "EventSticker\|MauGIF" ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/connector/handlematrix.go ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/connector/tomatrix.go

# Signal v0.2609.0
grep -n "CapMsgSticker\|CapMsgGIF" ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/connector/capabilities.go
grep -n "EventSticker\|MauGIF" ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/connector/handlematrix.go ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/connector/signal.go

# Telegram v0.2609.0
grep -n "CapMsgSticker\|CapMsgGIF" ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/connector/capabilities.go
grep -n "GetUserStickerPacks\|BridgedSticker" ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/connector/imagepack.go
grep -n "EventSticker\|MauGIF" ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/connector/tomatrix.go

# Google Messages v0.2609.0
grep -n "CapMsgSticker\|CapMsgGIF" ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/connector/capabilities.go

# Slack v0.2609.1
grep -n "CapMsgSticker\|CapMsgGIF" ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/capabilities.go
grep -n "StickerImportingNetworkAPI\|GetUserStickerPacks" ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/emoji.go
```

### 2. File path and `ledger.tsv` verification results

- `Modify paths: 56, missing: 0 | Create paths: 17, exist: 0, no parent: 0` (39 unique `Modify:` paths across tasks; 17 unique `Create:` paths)
- `rows cited: 10, failed lookups: 0`
