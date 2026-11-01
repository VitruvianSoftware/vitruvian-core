# Courier Milestone 4.7 — Appearance, Command Bar (`⌘J`), Storage & Provider Stubs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the seventh and final slice of Courier Milestone 4 (Spec §7 item 7): the Appearance system (Light/Dark/System theme mode, 8 clean-room Courier theme presets, custom accent & message bubble colours, 8 procedural vector wallpapers plus custom local wallpaper images, per-chat theme overrides with `ChatThemeWindow` and `ChatThemeBrowserWindow`, 8 clean-room procedural vector app icons plus custom icon upload, font-size scaling, `75%`–`150%` app zoom, streamer/demo `"Redact names and pictures"` privacy mode, confetti celebration overlay, and empty-state background/unread summary cards), the full §22 label and space icon catalog (`CourierIconCatalog` mapping all 151 Material-Symbol-named icon rows and 25 UI/hand-drawn icon rows to native macOS SF Symbols), the `⌘J` Command Bar (`CommandBarModel` + `CommandBarOverlay`) over a unified `CommandSet` registry aggregating every command registered across Milestones 4.1–4.7 (including nested sub-commands, `"Open recently viewed chats"`, and the `"Commands ⌘J"` switch inside `SearchPanel`), the Storage management pane (`StorageSettingsPane` + `StorageModel` backed by engine `storage.usage` and `storage.cleanup` RPCs in Protocol 11), and the five iteration-1 provider stubs (`AIProvider`, `GIFProvider`, `EntitlementProvider`, `ReportUploader`, `ThemeFileLoader`) plus every remaining calm `"not available yet"` screen (`Settings ▸ AI`, `AIPane`, `Talk to Type`, `Draft with AI`, `Translate`, slash commands, trial nudges, and `Settings ▸ Courier Plan` / `"Available with a plan"`).

**Architecture:**
- **Engine (`apps/desktop/courier/engine`, Go 1.26, JSON-RPC 2.0 over Unix socket, Protocol 10 → 11, SQLite Schema 10 unchanged):**
  - **Storage inspection & media cache cleanup (`engine/internal/store/storage.go`, `engine/internal/rpc/methods.go`):** Adds two JSON-RPC methods in Protocol 11 without changing the SQLite schema (`SchemaVersion` remains `10`):
    - `storage.usage` (`Empty` → `StorageUsageResult`): walks `events` (`kind`, `media_path`, `thumbnail_path`), `stickers` (`path`), `media.Store.Dir`, and the SQLite database files (`courier.db`, `courier.db-wal`, `courier.db-shm`) to report deduplicated byte totals by category (`images_bytes`, `videos_bytes`, `audio_bytes`, `files_bytes`, `stickers_bytes`, `database_bytes`, `cache_bytes`, `total_bytes`) and per-room media breakdowns (`rooms: [RoomStorageUsage]`, sorted by `total_bytes` descending).
    - `storage.cleanup` (`StorageCleanupParams { older_than_ms: Int64?, room_id: String? }` → `StorageCleanupResult { freed_bytes: Int64, deleted_blobs: Int, affected_rooms: Int }`): deletes cached media blobs from `media.Store` and clears `media_path` / `thumbnail_path` on matching `events` rows (scoped optionally to a single `room_id` and/or events with `ts < now - older_than_ms`) while preserving all message text, timeline event rows, and user-imported stickers (`pack_id = 'user'`), then publishes a `resync` change notification.
- **Core (`apps/desktop/courier/app/Sources/CourierCore`, Swift 6, `@MainActor` models, zero SwiftUI views):**
  - **Five Provider Stubs (`AIProvider.swift`, `GIFProvider.swift`, `Entitlement.swift`, `ProblemReportModel.swift`, `ThemeFileLoader.swift`):** Every external-service or unbuilt iteration-1 capability is backed by a protocol in `CourierCore` whose default iteration-1 implementation reports `isAvailable == false` with a calm, plain-English explanation and makes zero network requests (Spec §3):
    1. `AIProvider` + `UnavailableAIProvider` + `AIPreferences` (`AIProvider.swift`): backs `Settings ▸ AI`, `AIPane`, `Message: Talk to Type` (`⌘⇧D`), `Draft with AI`, `Translate` (`MessageTranslations`), voice-note Whisper transcription, and composer `/` slash commands.
    2. `GIFProvider` + `StubGIFProvider` (`GIFProvider.swift`): extended with `unavailableReason` so `GIFPickerPopover` reads its calm offline banner from the protocol seam.
    3. `EntitlementProvider` + `AlwaysEntitled` + `NoPlan` (`Entitlement.swift`, `engine/internal/entitlement/entitlement.go`): extended with `SubscriptionPlanSummary`, `PlanFeatureComparisonRow`, `SubscriptionExpiryBannerState`, and trial-nudge state (`FreebieNudge`) so `AlwaysEntitled` shows `"All Courier features are included on this Mac"` while `NoPlan` renders the calm `"Available with a plan"` comparison screen, `PlusPill`, and expiry/trial banners.
    4. `ReportUploader` + `UnavailableReportUploader` (`ProblemReportModel.swift`): injected into `ProblemReportModel` so `"Save Problem Report…"` writes a local scrubbed bundle while `"Send Report"` calmly explains that direct network upload isn't available yet.
    5. `ThemeFileLoader` + `UnavailableThemeFileLoader` (`ThemeFileLoader.swift`): injected into `AppearancePreferences` so the Custom CSS section in `Settings ▸ Appearance` renders real controls backed by a calm `"not available yet"` state without reading arbitrary stylesheet files.
  - **Appearance & Icon Models (`AppearancePreferences.swift`, `AppIconRenderer.swift`, `CourierIconCatalog.swift`):**
    - `AppearancePreferences` (`UserDefaults`-backed under `courier.appearance.*`, gated by `AppLockGate.shared.canPerform(.settingsChange)`): owns `themeMode` (`.system`, `.light`, `.dark`), `themePreset` (8 clean-room palettes), custom accent and outgoing/incoming bubble hex overrides, `perParticipantBubbleColors`, `defaultWallpaper` (8 clean-room procedural vector wallpapers + optional local image path, opacity, and blur), `chatThemes: [String: ChatThemeOverride]` (per-`roomID` theme/bubble/wallpaper overrides), `fontSizeScale` (`.extraSmall` through `.extraLarge`), `zoomPercent` (`75%`–`150%`), `reduceTransparency`, `redactNamesAndPictures` (deterministic pseudonym and avatar blur helper for screenshots/demos), `confettiTriggerCount`, `showEmptyStateBackground`, `showHoneycombCards`, and `selectedAppIcon`.
    - `AppIconRenderer`: draws 8 original procedural vector app icon variants using CoreGraphics (building on `apps/desktop/courier/app/scripts/make-icon.swift`'s squircle + folded-message-card geometry) and applies the selected or custom icon to `NSApplication.shared.applicationIconImage` via injectable `AppIconApplying`.
    - `CourierIconCatalog`: maps all 151 §22 Material-Symbol-named icon rows (`ac_unit.tsx` … `wine_bar.tsx`) and 25 §22 UI/hand-drawn icon rows to verified macOS SF Symbols with titles, categories, and search keywords, expanding `LabelsModel`'s allowed icon set while keeping `LabelsModel.icons` (the 30 default quick-pick icons) in their exact existing order.
  - **Command Bar (`CommandBarModel.swift`, `CommandSet.swift`, `HotkeyRegistry.swift`):**
    - `CommandSet.all(...)` aggregates every command from `CommandSet.inbox` (4.1), `CommandSet.search` (4.2), `CommandSet.message` (4.3/4.4), `CommandSet.accounts` (4.4), `CommandSet.chatInfo` (4.5a), `CommandSet.recordAudio` (4.5b), `CommandSet.composerMedia` (4.5c), `CommandSet.settingsAndSystem` (4.6), and the new 4.7 navigation, filter, label, reminder, appearance, zoom, storage, and stub commands — including nested sub-command trees (`Filter Chats ▸`, `Remind Later ▸`, `Label ▸`, `Go to Space ▸`, `Theme ▸`, `Disappearing Messages ▸`) and `"Open recently viewed chats"`.
    - `CommandBarModel` ranks commands by prefix, word-boundary, and substring match across `title`, `subtitle`, `category`, and `keywords`, boosts recently run commands on an empty query, tracks nested breadcrumbs, routes confirmations through `Confirm.run`, and closes immediately when `SystemLifecycleModel` locks.
- **UI (`apps/desktop/courier/app/Sources/Courier`, SwiftUI + AppKit):**
  - `CommandBarOverlay.swift` (`CommandBar.tsx`, `CommandBarFooter.tsx`, `SelectMessageCommand.tsx`, `SelectRecentSearchCommand.tsx`, `ConfettiIcon.tsx`) and `SearchPanel.swift` (`"Commands ⌘J"` switch pill).
  - `GeneralSettingsPane.swift` (expanded `AppearanceSettingsPane`), `AppIconPickerView.swift` (`AppIconPrefsSubView.tsx`), `ChatThemeWindow.swift` (`ChatThemeWindow.tsx`, `ChatThemeBrowserWindow.tsx`), `StorageSettingsPane.swift` (`StoragePrefsSubView.tsx`, `StorageOverviewChart.tsx`, `StorageByRoomList.tsx`), `AISettingsPane.swift`, `AIPane.swift` (`AIPane.tsx`, `AIMessageContent.tsx`, `AIMessageFooterActions.tsx`, `AIMessageParts.tsx`, `AIModelButton.tsx`, `AISpinnerVerb.tsx`, `AIToolCallsPanel.tsx`), and `PlusSettingsPane.swift` (`PlusPill.tsx`, `FreebieNudge.tsx`, `SubscriptionExpiryBanners.tsx`, `BrowserExtPrefsSubView.tsx`, `MobileAppsPrefsSubView.tsx`, `SecretPrefsSubView.tsx`, `DebugPreferencesIndex.tsx`).
  - `ViewSnapshotTests.swift` light + dark PNG snapshot verification across every new pane, window, overlay, and stub state.

**Tech Stack:** Go 1.26 (`modernc.org/sqlite`), Swift 6 (`SwiftUI`, `AppKit`, `CoreGraphics`), Bazel (`//apps/desktop/courier/...`).

**Split decision:** Single self-contained plan (`10` tasks). Milestone 4.7 is the final Milestone 4 slice and touches only two new engine read/cleanup RPCs (`storage.usage`, `storage.cleanup`) plus local `CourierCore` models and `Courier` views. Every task ends with green `bazel test //apps/desktop/courier/...` targets.

---

## Summary for the Owner

### What works after Milestone 4.7
1. **Command Bar (`⌘J`) over the unified command registry (`CommandBarOverlay`, `CommandBarModel`, `CommandSet`):**
   - Pressing `⌘J` (or choosing `Courier ▸ Command Bar…`, or pressing the global shortcut `⌘⇧Space`, or clicking `"Commands ⌘J"` inside the `⌘K` search panel) opens the floating Command Bar over the main window.
   - Every command registered across Milestones 4.1–4.7 appears in one searchable list with category headers, right-aligned shortcut keycaps, and contextual subtitles (for example, `"Pin “Design Review”"` or `"Turn off Incognito mode"`).
   - Multi-step commands (`Filter Chats`, `Remind Later`, `Label…`, `Go to Space…`, `Set Theme…`, `Disappearing Messages…`) drill into nested sub-commands with a breadcrumb pill (`Filter Chats ▸`) and `⌫` to pop back; `"Open recently viewed chats"` lists your recent chats right inside the Command Bar; and destructive or bulk commands (`Archive all chats`, `Delete Media…`, `Leave Group`, `Delete Chat`) ask for confirmation first.
2. **Themes, Colours, Wallpapers, Per-Chat Themes, App Icons, Font Size, Zoom & Redact Mode (`AppearancePreferences`, `ChatThemeWindow`, `ChatThemeBrowserWindow`, `AppIconPickerView`):**
   - `Settings ▸ Appearance` (`⌘,`) adds 8 clean-room Courier theme presets (`Classic Teal`, `Slate`, `Midnight Indigo`, `Warm Paper`, `Evergreen`, `Sunset Coral`, `Rose Quartz`, `Ocean Deep`) on top of `System` / `Light` / `Dark`, custom accent and outgoing/incoming message bubble colour pickers, per-participant group sender colours, and 8 procedural vector wallpapers (`None`, `Subtle Grid`, `Topographic Lines`, `Soft Waves`, `Starfield`, `Aurora Glow`, `Dot Matrix`, `Paper Grain`) plus custom local image wallpapers with opacity and blur controls.
   - Any individual chat can override the default theme, bubble colour, and wallpaper via `Chat Theme…` in the chat's right-click menu, `Chat Info`, or `⌘J` (`ChatThemeWindow`), and `"Browse Chat Themes…"` opens a live preview gallery (`ChatThemeBrowserWindow`).
   - `App Icon` in `Settings ▸ Appearance` offers 8 original CoreGraphics-drawn Courier icons (`Classic Teal`, `Midnight Indigo`, `Sunset Amber`, `Emerald Forest`, `Monochrome Slate`, `Warm Paper`, `Violet Pulse`, `Copper Craft`) plus `"Choose Custom Icon…"` (`PNG`, `JPG`, or `ICNS`), updating the macOS Dock icon immediately.
   - `Font size` (`Extra Small` 85% through `Extra Large` 125%) scales message bubbles, inbox previews, and the composer; `Zoom In` (`⌘+`), `Zoom Out` (`⌘-`), and `Actual Size` (`⌘0`) scale the interface from `75%` to `150%`; `"Redact names and pictures"` blurs avatars and replaces chat/sender names with deterministic pseudonyms for safe screen-sharing; and `"Confetti"` celebrates with a lightweight particle burst that honours macOS Reduce Motion.
3. **Full §22 Label & Space Icon Library (`CourierIconCatalog`, `IconColorPicker`):**
   - Creating or editing a label opens a searchable, categorized icon picker covering all 151 §22 icon-library rows mapped to native macOS SF Symbols while keeping the 30 default icons at the top.
4. **Storage Management (`Settings ▸ Storage`, `storage.usage`, `storage.cleanup`):**
   - `Settings ▸ Storage` displays a segmented breakdown chart (`Images`, `Videos`, `Audio`, `Other Files`, `Stickers`, `Messages & Database`) and a per-chat media list sorted by size.
   - You can delete media in a single chat (`"Delete media in this chat"`), delete media older than `1 week`, `1 month`, `3 months`, or `1 year` (`"Delete media older than …"`), or delete all media on this Mac (`"Delete Media…"` with confirmation `"This deletes photos, videos and files from this Mac. Messages stay, but the media can't be brought back."`) without deleting any message text or chat history.
5. **The Five Provider Stubs & Calm "Not Available Yet" Screens (`AIProvider`, `GIFProvider`, `EntitlementProvider`, `ReportUploader`, `ThemeFileLoader`):**
   - Every stubbed capability (`Settings ▸ AI`, the right-hand `AIPane`, `Message: Talk to Type` `⌘⇧D`, `Draft with AI`, message `Translate`, composer `/` slash commands, online GIF search in `GIFPickerPopover`, `Settings ▸ Courier Plan` / `"Available with a plan"`, direct problem-report upload in `ProblemReportSheet`, Custom CSS in `Settings ▸ Appearance`, and `Settings ▸ Integrations`) renders a complete, calm macOS interface backed by its protocol in `CourierCore` and makes **zero** network calls.

---

## Global Constraints (Enforced Across All 10 Tasks)

1. **Zero Unrequested Network Traffic & Clean-Room Privacy:**
   - None of the five provider stubs (`UnavailableAIProvider`, `StubGIFProvider`, `AlwaysEntitled` / `NoPlan`, `UnavailableReportUploader`, `UnavailableThemeFileLoader`) may open a socket, import `URLSession` for outbound calls, or contact OpenAI, Tenor, Giphy, Sentry, or any external server.
   - Every app icon, theme palette, and wallpaper in Courier is our own original CoreGraphics / SwiftUI vector artwork. Never copy Beeper artwork, CSS, or strings; user-visible strings always say `Courier`, never `Beeper` (raw inventory ledger keys like `setting:beeper-plus Go Unlimited` or `menu:Beeper Command Bar…` appear only in code comments, setting search anchor IDs where internal, and ledger tables).
2. **`AppLockGate` Enforcement Across Every New Surface:**
   - While `AppLockGate.shared.isLocked` is `true`:
     - `CommandBarModel` refuses `open()`, `toggle()`, and `runSelected()`, and automatically dismisses `isPresented = false` when `SystemLifecycleModel.didLockNotification` fires.
     - `AppearancePreferences`, `AIPreferences`, and `StorageModel` guard every `@Published` setter and action with `AppLockGate.shared.canPerform(.settingsChange)` (or `.other`), reverting mutations attempted while locked.
     - `storage.usage` and `storage.cleanup` are classified as `.userInitiatedMutation` in `ProtocolMethods.classifications` so `EngineClient.call` refuses them while locked.
     - `ChatThemeWindow` and `ChatThemeBrowserWindow` wrap their content in `LockableWindowContent(lifecycle:)` so locking Courier covers them with `AppLockOverlay` and scrubs their window titles to `"Courier"`.
     - All file-picking panels (`Custom Wallpaper…`, `Custom App Icon…`, `Custom Theme File…`) route through `AppLockGate.shared.runOpenPanel` so locking Courier mid-dialog aborts the modal panel immediately.
3. **Strict `CourierCore` / `Courier` Separation:**
   - All models, command registries, preference stores, icon catalogs, and provider protocols live in `CourierCore` with deterministic unit tests in `CourierCoreTests`.
   - SwiftUI views and `NSApplication` / `NSWindow` / `NSOpenPanel` adapters live in `Courier` (or behind protocols in `CourierCore`) and are verified by light and dark PNG snapshots in `CourierViewTests`.

---

## Review Focus (Risks Watched Closest)

1. **Every 4.1–4.7 Command Reachable and Executable in `⌘J`:**
   - Earlier milestones registered commands in `CommandSet.inbox`, `CommandSet.search`, `CommandSet.message`, `CommandSet.accounts`, `CommandSet.chatInfo`, `CommandSet.recordAudio`, `CommandSet.composerMedia`, and `CommandSet.settingsAndSystem` with the note `"registered; shown in ⌘J by 4.7"`. Task 5 must wire every single one of those groups — plus the remaining `m4-acceptance.md` and `ledger.tsv` command rows (`Filter Chats`, `Filter by folder type`, `Filter by type`, `Filter by account`, `Toggle chat selection mode`, `Show message requests`, `Edit spaces`, `Open recently viewed chats`, `Send later`, `Create quick reply from draft`, `Edit`, `Forward`, `Unsend`, `Delete for me`, `Reply in thread`, `Add Account`, `Account`, `Accounts`, `Turn on/off incognito mode`, `Zoom in/out/Reset zoom`, `Set theme to light/dark mode`, `Confetti`, `Redact names and pictures`, `Cleanup`, etc.) — into `CommandSet.all(...)` and verify them in `CommandSetTests`.
2. **Safe Media Cleanup (`storage.cleanup`):**
   - Clearing cached media in `Settings ▸ Storage` must never delete SQLite event rows (`events`), message bodies, or user-imported stickers (`stickers` rows with `pack_id = 'user'`). If a blob hash is still referenced by another event that was *not* selected for cleanup (or by a user-imported sticker), `storage.cleanup` clears `media_path` / `thumbnail_path` on the targeted events without unlinking the shared file on disk until zero remaining references exist.
3. **Accessibility Reduce Motion & High Contrast / Transparency:**
   - `ConfettiOverlayView` and wallpaper animations must check `accessibilityReduceMotion` (mirroring `StickerAttachmentView.shouldAnimate` in `MessageBubble.swift`) so enabling Reduce Motion in macOS System Settings suppresses particle motion.
   - Turning on `"Reduce transparency"` (`AppearancePreferences.reduceTransparency`) replaces translucent window/sidebar materials and wallpaper blur with opaque surface fills.

---

### Task 1: Protocol 11 — Engine Storage Usage & Media Cache Cleanup (`storage.usage`, `storage.cleanup`)

**Files:**
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Create: `apps/desktop/courier/protocol/examples/storage-usage.json`
- Create: `apps/desktop/courier/protocol/examples/storage-cleanup.json`
- Create: `apps/desktop/courier/engine/internal/store/storage.go`
- Create: `apps/desktop/courier/engine/internal/store/storage_test.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/server.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/methods.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/conformance_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/BUILD`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ProtocolConformanceTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/EngineClientTests.swift`

**Interfaces:**

```go
// apps/desktop/courier/engine/internal/store/storage.go
package store

type RoomStorageUsage struct {
	RoomID      string `json:"room_id"`
	Name        string `json:"name"`
	Network     string `json:"network"`
	IsDirect    bool   `json:"is_direct"`
	ImagesBytes int64  `json:"images_bytes"`
	VideosBytes int64  `json:"videos_bytes"`
	AudioBytes  int64  `json:"audio_bytes"`
	FilesBytes  int64  `json:"files_bytes"`
	TotalBytes  int64  `json:"total_bytes"`
	ItemCount   int    `json:"item_count"`
}

type StorageUsage struct {
	ImagesBytes   int64              `json:"images_bytes"`
	VideosBytes   int64              `json:"videos_bytes"`
	AudioBytes    int64              `json:"audio_bytes"`
	FilesBytes    int64              `json:"files_bytes"`
	StickersBytes int64              `json:"stickers_bytes"`
	DatabaseBytes int64              `json:"database_bytes"`
	CacheBytes    int64              `json:"cache_bytes"`
	TotalBytes    int64              `json:"total_bytes"`
	Rooms         []RoomStorageUsage `json:"rooms"`
}

type StorageCleanupFilter struct {
	OlderThanMS *int64
	RoomID      *string
}

type StorageCleanupReport struct {
	FreedBytes    int64 `json:"freed_bytes"`
	DeletedBlobs  int   `json:"deleted_blobs"`
	AffectedRooms int   `json:"affected_rooms"`
}

func (s *Store) StorageUsage(ctx context.Context, dbPath string) (StorageUsage, error)
func (s *Store) CleanupStorage(ctx context.Context, filter StorageCleanupFilter) (StorageCleanupReport, error)
```

```swift
// apps/desktop/courier/app/Sources/CourierCore/Protocol.swift
public enum CourierProtocol {
    public static let version = 11
    public static let schemaVersion = 10
    public static let maxFrameBytes = 4_194_304
    public static let typingRepeatMillis = 4000
}

public struct RoomStorageUsage: ProtocolType, Identifiable {
    public static let protocolName = "RoomStorageUsage"
    public static let fieldNames = [
        "room_id", "name", "network", "is_direct",
        "images_bytes", "videos_bytes", "audio_bytes", "files_bytes",
        "total_bytes", "item_count",
    ]
    public let roomID: String
    public let name: String
    public let network: String
    public let isDirect: Bool
    public let imagesBytes: Int64
    public let videosBytes: Int64
    public let audioBytes: Int64
    public let filesBytes: Int64
    public let totalBytes: Int64
    public let itemCount: Int
    public var id: String { roomID }
}

public struct StorageUsageResult: ProtocolType {
    public static let protocolName = "StorageUsageResult"
    public static let fieldNames = [
        "images_bytes", "videos_bytes", "audio_bytes", "files_bytes",
        "stickers_bytes", "database_bytes", "cache_bytes", "total_bytes",
        "rooms",
    ]
    public let imagesBytes: Int64
    public let videosBytes: Int64
    public let audioBytes: Int64
    public let filesBytes: Int64
    public let stickersBytes: Int64
    public let databaseBytes: Int64
    public let cacheBytes: Int64
    public let totalBytes: Int64
    public let rooms: [RoomStorageUsage]
}

public struct StorageCleanupParams: ProtocolType {
    public static let protocolName = "StorageCleanupParams"
    public static let fieldNames = ["older_than_ms", "room_id"]
    public let olderThanMS: Int64?
    public let roomID: String?
    public init(olderThanMS: Int64? = nil, roomID: String? = nil) {
        self.olderThanMS = olderThanMS
        self.roomID = roomID
    }
}

public struct StorageCleanupResult: ProtocolType {
    public static let protocolName = "StorageCleanupResult"
    public static let fieldNames = ["freed_bytes", "deleted_blobs", "affected_rooms"]
    public let freedBytes: Int64
    public let deletedBlobs: Int
    public let affectedRooms: Int
}
```

**Steps:**
- [ ] **Step 1: Write failing Go unit tests (`engine/internal/store/storage_test.go`) and Swift protocol conformance tests (`ProtocolConformanceTests.swift`).**
  - Create `apps/desktop/courier/engine/internal/store/storage_test.go` testing:
    - `TestStorageUsageCategorizesMediaStickersDatabaseAndPerRoomTotals`: seeds two rooms (`!wa1`, `!sig1`) with image (`m.image`), video (`m.video`), voice/audio (`m.audio`), and file (`m.file`) events backed by real blobs in `media.Store`, plus a sticker in `stickers` and an unreferenced orphan blob in `media.Store.Dir`. Asserts `StorageUsage` reports exact byte counts per category, counts shared blobs once in top-level category totals while attributing per-room bytes in `Rooms`, orders `Rooms` by `TotalBytes` descending, and counts orphan blobs under `CacheBytes`.
    - `TestCleanupStorageByAgeAndRoomPreservesEventsAndSharedOrUserStickerBlobs`: runs `CleanupStorage` with `RoomID: "!wa1"` and with `OlderThanMS: 7 * 86400_000`. Verifies:
      1. `events` rows remain in SQLite with their body/metadata intact while `media_path` and `thumbnail_path` on cleaned events become `""`.
      2. A blob shared with `!sig1` or with a user-imported sticker (`pack_id = 'user'`) is **not** removed from disk until no remaining event or sticker references it.
      3. Unreferenced blobs in `media.Store` are removed and their byte size is included in `FreedBytes`.
      4. Passing an unknown `room_id` or `"merge:abc"` returns `ErrNotFound` (`-32020`); passing a negative `older_than_ms` returns `ErrBadValue` (`-32014`).
- [ ] **Step 2: Implement `store/storage.go` and wire `storage.usage` + `storage.cleanup` in `rpc/server.go` and `rpc/methods.go`.**
  - Bump `Protocol` from `10` to `11` in `apps/desktop/courier/engine/internal/rpc/server.go`, `apps/desktop/courier/protocol/protocol.json`, and `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`.
  - Add `RoomStorageUsage`, `StorageUsageResult`, `StorageCleanupParams`, and `StorageCleanupResult` to `protocol.json` and `Protocol.swift`, classify `"storage.usage": .userInitiatedMutation` and `"storage.cleanup": .userInitiatedMutation` in `ProtocolMethods.classifications`, and add `apps/desktop/courier/protocol/examples/storage-usage.json` and `storage-cleanup.json`.
  - Register `storage.go` and `storage_test.go` in `apps/desktop/courier/engine/internal/store/BUILD`.
- [ ] **Step 3: Run Go and Swift protocol/store tests.**

**Tests:**
```bash
bazel test //apps/desktop/courier/engine/internal/store:store_test \
  //apps/desktop/courier/engine/internal/rpc:rpc_test \
  //apps/desktop/courier/app:CourierCoreTests --test_filter=ProtocolConformanceTests
```

---

### Task 2: The Five Provider Stubs (`AIProvider`, `GIFProvider`, `EntitlementProvider`, `ReportUploader`, `ThemeFileLoader`) & Calm "Not Available Yet" Seams

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/AIProvider.swift`
- Create: `apps/desktop/courier/app/Sources/CourierCore/ThemeFileLoader.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/GIFProvider.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Entitlement.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ProblemReportModel.swift`
- Modify: `apps/desktop/courier/engine/internal/entitlement/entitlement.go`
- Create: `apps/desktop/courier/engine/internal/entitlement/entitlement_test.go`
- Modify: `apps/desktop/courier/engine/internal/entitlement/BUILD`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/ProviderStubsTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/EntitlementTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/GIFProviderTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ProblemReportModelTests.swift`

**Interfaces:**

```swift
// apps/desktop/courier/app/Sources/CourierCore/AIProvider.swift
import Combine
import Foundation

public enum AIEngineChoice: String, CaseIterable, Codable, Sendable {
    case appleIntelligence
    case openAI
    case customOpenAICompatible

    public var label: String {
        switch self {
        case .appleIntelligence: String(localized: "Apple Intelligence (On-Device)")
        case .openAI: String(localized: "OpenAI")
        case .customOpenAICompatible: String(localized: "Custom OpenAI-Compatible Endpoint")
        }
    }
}

public enum AIRewriteTone: String, CaseIterable, Codable, Sendable {
    case fixGrammar
    case moreConcise
    case moreConfident
    case moreFriendly
    case moreProfessional
    case moreVerbose

    public var label: String {
        switch self {
        case .fixGrammar: String(localized: "Fix grammar and spelling")
        case .moreConcise: String(localized: "Make more concise")
        case .moreConfident: String(localized: "Make more confident")
        case .moreFriendly: String(localized: "Make more friendly")
        case .moreProfessional: String(localized: "Make more professional")
        case .moreVerbose: String(localized: "Make more verbose")
        }
    }
}

public enum AIProviderDisposition: Equatable, Sendable {
    case unavailable(reason: String)
    case text(String)
}

/// Spec §3 seam for AI features (Settings ▸ AI, AIPane, Talk to Type, Draft with AI, Translate, Whisper transcription).
/// Iteration 1's `UnavailableAIProvider` is completely offline and never contacts any server.
public protocol AIProvider: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    var availableModels: [String] { get }
    func draftResponse(roomID: String, prompt: String, tone: AIRewriteTone?) async -> AIProviderDisposition
    func translate(text: String, targetLanguage: String) async -> AIProviderDisposition
    func summarize(roomID: String, eventIDs: [String]) async -> AIProviderDisposition
    func transcribeVoiceNote(roomID: String, eventID: String) async -> AIProviderDisposition
    func startTalkToType() async -> AIProviderDisposition
}

public struct UnavailableAIProvider: AIProvider {
    public init() {}
    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        String(localized: "AI features aren’t available yet in Courier. Everything you write stays on this Mac.")
    }
    public var availableModels: [String] {
        [String(localized: "On-Device (Not available yet)")]
    }
    public func draftResponse(roomID _: String, prompt _: String, tone _: AIRewriteTone?) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Drafting with AI isn’t available yet in Courier."))
    }
    public func translate(text _: String, targetLanguage _: String) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Message translation isn’t available yet in Courier."))
    }
    public func summarize(roomID _: String, eventIDs _: [String]) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "AI chat summaries aren’t available yet in Courier."))
    }
    public func transcribeVoiceNote(roomID _: String, eventID _: String) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Voice-note transcription isn’t available yet in Courier."))
    }
    public func startTalkToType() async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Talk to Type isn’t available yet in Courier."))
    }
}

@MainActor
public final class AIPreferences: ObservableObject {
    @Published public var enableContextualAI: Bool
    @Published public var selectedEngine: AIEngineChoice
    @Published public var selectedModel: String
    @Published public var responseLanguage: String
    @Published public var translationLanguages: [String]
    @Published public var mentionAIInChats: Bool
    @Published public var aiMentionsSystemPrompt: String
    @Published public var useWhisperForTalkToType: Bool
    @Published public var autoTranscribeVoiceNotes: Bool
    @Published public var transcriptionLanguage: String
    @Published public var enableSlashCommands: Bool

    public static let supportedTranslationLanguages: [String] = [
        "Arabic", "Chinese (Simplified)", "Chinese (Traditional)", "Dutch",
        "English", "French", "German", "Hindi", "Italian", "Japanese",
        "Korean", "Polish", "Portuguese", "Russian", "Spanish", "Turkish", "Vietnamese",
    ]
    public static func key(_ name: String) -> String { "courier.ai." + name }
    public init(defaults: UserDefaults = .standard)
}
```

```swift
// apps/desktop/courier/app/Sources/CourierCore/ThemeFileLoader.swift
import Foundation

public struct CustomThemeStylesheet: Equatable, Sendable {
    public let path: String
    public let css: String
    public let loadedAt: Date
}

public enum ThemeFileLoaderDisposition: Equatable, Sendable {
    case unavailable(reason: String)
    case loaded(CustomThemeStylesheet)
}

/// Spec §3 seam for loading custom CSS / theme files in Settings ▸ Appearance.
public protocol ThemeFileLoader: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func loadThemeFile(at url: URL) -> ThemeFileLoaderDisposition
    func reload() -> ThemeFileLoaderDisposition
    func reset()
}

public struct UnavailableThemeFileLoader: ThemeFileLoader {
    public init() {}
    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        String(localized: "Custom CSS and external theme files aren’t available yet in Courier. Use the built-in themes, colours, and wallpapers above.")
    }
    public func loadThemeFile(at _: URL) -> ThemeFileLoaderDisposition {
        .unavailable(reason: unavailableReason)
    }
    public func reload() -> ThemeFileLoaderDisposition {
        .unavailable(reason: unavailableReason)
    }
    public func reset() {}
}
```

```swift
// Additions to apps/desktop/courier/app/Sources/CourierCore/ProblemReportModel.swift
public enum ReportUploadDisposition: Equatable, Sendable {
    case unavailable(reason: String)
    case uploaded(referenceID: String)
}

/// Spec §3 seam for uploading scrubbed problem reports. Iteration 1's `UnavailableReportUploader`
/// is offline-only and directs the person to save the scrubbed bundle locally on this Mac.
public protocol ReportUploader: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func upload(bundleURL: URL, description: String) async -> ReportUploadDisposition
}

public struct UnavailableReportUploader: ReportUploader {
    public init() {}
    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        String(localized: "Direct report upload isn’t available yet in Courier. Save a scrubbed problem report on this Mac instead.")
    }
    public func upload(bundleURL _: URL, description _: String) async -> ReportUploadDisposition {
        .unavailable(reason: unavailableReason)
    }
}
```

```swift
// Additions to apps/desktop/courier/app/Sources/CourierCore/Entitlement.swift
public struct PlanFeatureComparisonRow: Equatable, Sendable, Identifiable {
    public let feature: Feature
    public let title: String
    public let summary: String
    public let freeValue: String
    public let planValue: String
    public let isAllowedNow: Bool
    public var id: Feature { feature }
}

public enum SubscriptionExpiryBannerState: Equatable, Sendable {
    case activeIncluded
    case trialActive(daysRemaining: Int)
    case expiringSoon(dateText: String)
    case expired
}

public struct SubscriptionPlanSummary: Equatable, Sendable {
    public let badgeTitle: String
    public let headline: String
    public let detail: String
    public let accountsPerNetworkLimit: String
    public let totalAccountsLimit: String
    public let mergedChatsLimit: String
    public let bannerState: SubscriptionExpiryBannerState
    public let featureRows: [PlanFeatureComparisonRow]
}

extension EntitlementProvider {
    public var planSummary: SubscriptionPlanSummary { ... }
    public func freebieNudgeText(for feature: Feature) -> String? { ... }
}
```

**Steps:**
- [ ] **Step 1: Write failing unit tests in `ProviderStubsTests.swift`, `EntitlementTests.swift`, `GIFProviderTests.swift`, `ProblemReportModelTests.swift`, and `engine/internal/entitlement/entitlement_test.go`.**
  - Test that `UnavailableAIProvider`, `StubGIFProvider`, `UnavailableReportUploader`, and `UnavailableThemeFileLoader` all report `isAvailable == false`, return non-empty localized `unavailableReason` strings containing `"Courier"` (never `"Beeper"`), and complete synchronously/asynchronously with zero network I/O.
  - Test that `AIPreferences` persists every setting in `UserDefaults`, defaults `enableContextualAI == false`, `useWhisperForTalkToType == false`, `autoTranscribeVoiceNotes == false`, `mentionAIInChats == false`, and `translationLanguages == ["English"]`, and reverts any mutation attempted while `AppLockGate.shared.isLocked` is `true`.
  - Test that `AlwaysEntitled.planSummary` reports all 6 `Feature` rows as allowed (`badgeTitle == "Included"`, `bannerState == .activeIncluded`, `freebieNudgeText(for:) == nil`), while `NoPlan.planSummary` reports all 6 `Feature` rows as gated (`badgeTitle == "Free"`, `headline == "Available with a plan"`, `freebieNudgeText(for: .incognito) == "Available with a plan"`).
  - Test that `ProblemReportModel.attemptUpload()` invokes `reportUploader.upload(...)` and sets `uploadNotice = reportUploader.unavailableReason` when `UnavailableReportUploader` is used.
- [ ] **Step 2: Implement `AIProvider.swift`, `ThemeFileLoader.swift`, and the extensions on `GIFProvider.swift`, `Entitlement.swift`, `ProblemReportModel.swift`, and `engine/internal/entitlement/entitlement.go`.**
- [ ] **Step 3: Run Go and Swift tests.**

**Tests:**
```bash
bazel test //apps/desktop/courier/engine/internal/entitlement:entitlement_test \
  //apps/desktop/courier/app:CourierCoreTests --test_filter="ProviderStubsTests|EntitlementTests|GIFProviderTests|ProblemReportModelTests"
```

---

### Task 3: `AppearancePreferences` Model — Themes, Colours, Wallpapers, Per-Chat Themes, Font Size, Zoom, App Icons (Our Own Art), Redact Mode & Confetti

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/AppearancePreferences.swift`
- Create: `apps/desktop/courier/app/Sources/CourierCore/AppIconRenderer.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/AppearancePreferencesTests.swift`

**Interfaces:**

```swift
// apps/desktop/courier/app/Sources/CourierCore/AppearancePreferences.swift
import AppKit
import Combine
import Foundation

public enum ThemeMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

public enum CourierThemePreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case classicTeal
    case slate
    case midnightIndigo
    case warmPaper
    case evergreen
    case sunsetCoral
    case roseQuartz
    case oceanDeep

    public var id: String { rawValue }
    public var title: String { ... }
    public var defaultAccentHex: String { ... }
    public var defaultOutgoingBubbleHexLight: String { ... }
    public var defaultOutgoingBubbleHexDark: String { ... }
    public var defaultIncomingBubbleHexLight: String { ... }
    public var defaultIncomingBubbleHexDark: String { ... }
    public var canvasTintHexLight: String { ... }
    public var canvasTintHexDark: String { ... }
}

public enum CourierWallpaperPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case subtleGrid
    case topographicLines
    case softWaves
    case starfield
    case auroraGlow
    case dotMatrix
    case paperGrain

    public var id: String { rawValue }
    public var title: String { ... }
    public var subtitle: String { ... }
}

public enum FontSizeScale: String, CaseIterable, Codable, Sendable, Identifiable {
    case extraSmall
    case small
    case `default`
    case large
    case extraLarge

    public var id: String { rawValue }
    public var label: String { ... }
    public var multiplier: CGFloat {
        switch self {
        case .extraSmall: 0.85
        case .small: 0.92
        case .default: 1.0
        case .large: 1.10
        case .extraLarge: 1.25
        }
    }
    public var messageBodyPointSize: CGFloat { round(13.0 * multiplier * 2) / 2 }
    public var inboxPreviewPointSize: CGFloat { round(12.0 * multiplier * 2) / 2 }
}

public struct ChatThemeOverride: Codable, Equatable, Sendable {
    public var preset: CourierThemePreset?
    public var accentColorHex: String?
    public var outgoingBubbleColorHex: String?
    public var incomingBubbleColorHex: String?
    public var wallpaper: CourierWallpaperPreset?
    public var customWallpaperPath: String?
    public var wallpaperOpacity: Double?
    public var wallpaperBlur: Bool?

    public init(
        preset: CourierThemePreset? = nil,
        accentColorHex: String? = nil,
        outgoingBubbleColorHex: String? = nil,
        incomingBubbleColorHex: String? = nil,
        wallpaper: CourierWallpaperPreset? = nil,
        customWallpaperPath: String? = nil,
        wallpaperOpacity: Double? = nil,
        wallpaperBlur: Bool? = nil
    )
}

public struct ResolvedChatTheme: Equatable, Sendable {
    public let preset: CourierThemePreset
    public let accentColorHex: String
    public let outgoingBubbleHexLight: String
    public let outgoingBubbleHexDark: String
    public let incomingBubbleHexLight: String
    public let incomingBubbleHexDark: String
    public let wallpaper: CourierWallpaperPreset
    public let customWallpaperPath: String?
    public let wallpaperOpacity: Double
    public let wallpaperBlur: Bool
    public let isOverriddenForRoom: Bool
}

@MainActor
public final class AppearancePreferences: ObservableObject {
    public static let zoomSteps: [Int] = [75, 80, 90, 100, 110, 125, 150]

    @Published public var themeMode: ThemeMode
    @Published public var themePreset: CourierThemePreset
    @Published public var accentColorHex: String?
    @Published public var outgoingBubbleColorHex: String?
    @Published public var incomingBubbleColorHex: String?
    @Published public var perParticipantBubbleColors: Bool
    @Published public var defaultWallpaper: CourierWallpaperPreset
    @Published public var customWallpaperPath: String?
    @Published public var wallpaperOpacity: Double
    @Published public var wallpaperBlur: Bool
    @Published public private(set) var chatThemes: [String: ChatThemeOverride]
    @Published public var fontSizeScale: FontSizeScale
    @Published public var zoomPercent: Int
    @Published public var reduceTransparency: Bool
    @Published public var enableMessageAnimations: Bool
    @Published public var balanceMessageText: Bool
    @Published public var usePointerCursor: Bool
    @Published public var showFeedbackWidget: Bool
    @Published public var showEmptyStateBackground: Bool
    @Published public var showHoneycombCards: Bool
    @Published public var redactNamesAndPictures: Bool
    @Published public var selectedAppIcon: CourierAppIconVariant
    @Published public var customAppIconPath: String?
    @Published public private(set) var confettiTriggerCount: Int
    @Published public private(set) var lastThemeFileNotice: String?

    public let themeFileLoader: any ThemeFileLoader
    public let appIconApplier: any AppIconApplying

    public init(
        defaults: UserDefaults = .standard,
        themeFileLoader: any ThemeFileLoader = UnavailableThemeFileLoader(),
        appIconApplier: any AppIconApplying = MACAppIconApplier()
    )

    public func effectiveTheme(for roomID: String?) -> ResolvedChatTheme
    public func setChatTheme(_ override: ChatThemeOverride, for roomID: String)
    public func resetChatTheme(for roomID: String)
    public func resetAllChatThemes()
    public func zoomIn()
    public func zoomOut()
    public func resetZoom()
    public func increaseFontSize()
    public func decreaseFontSize()
    public func resetFontSize()
    public func fireConfetti()
    public func attemptLoadCustomThemeFile(at url: URL) -> ThemeFileLoaderDisposition
    public func reloadCustomThemeFile() -> ThemeFileLoaderDisposition
    public static func redactedText(_ original: String, kind: RedactedTextKind = .name) -> String
    public static func participantBubbleColorHex(for senderID: String, isDark: Bool) -> String
}
```

```swift
// apps/desktop/courier/app/Sources/CourierCore/AppIconRenderer.swift
import AppKit
import CoreGraphics
import Foundation

public enum CourierAppIconVariant: String, CaseIterable, Codable, Sendable, Identifiable {
    case classicTeal
    case midnightIndigo
    case sunsetAmber
    case emeraldForest
    case monochromeSlate
    case warmPaper
    case violetPulse
    case copperCraft

    public var id: String { rawValue }
    public var title: String { ... }
    public var subtitle: String { ... }
}

@MainActor
public protocol AppIconApplying: AnyObject {
    var appliedVariant: CourierAppIconVariant? { get }
    var appliedCustomPath: String? { get }
    func apply(variant: CourierAppIconVariant)
    func applyCustomImage(at path: String) throws
}

public enum AppIconRenderer {
    /// Draws our own clean-room procedural vector Courier app icon (rounded squircle + stacked message cards + accent badge)
    /// at the requested pixel dimension (e.g. 128, 256, 512, 1024). Zero external asset files.
    public static func renderIcon(variant: CourierAppIconVariant, size: Int = 256) -> NSImage
}
```

**Steps:**
- [ ] **Step 1: Write failing unit tests in `AppearancePreferencesTests.swift`.**
  - Test `testDefaultsMatchTheInventoryAndPersistToUserDefaults`: verifies out-of-the-box defaults (`themeMode == .system`, `themePreset == .classicTeal`, `defaultWallpaper == .none`, `fontSizeScale == .default`, `zoomPercent == 100`, `reduceTransparency == false`, `enableMessageAnimations == true`, `balanceMessageText == true`, `usePointerCursor == false`, `showFeedbackWidget == false`, `redactNamesAndPictures == false`, `selectedAppIcon == .classicTeal`) and round-trip persistence across a fresh `AppearancePreferences(defaults:)` instance.
  - Test `testPerChatThemeOverrideMergesAndResetsCleanly`: sets a `ChatThemeOverride` on `"!room1:courier.local"`, verifies `effectiveTheme(for: "!room1:courier.local")` applies the room's preset/bubble/wallpaper while `"!room2:courier.local"` uses the global default, and verifies `resetChatTheme(for:)` and `resetAllChatThemes()`.
  - Test `testZoomAndFontSizeSteppingClampsToBounds`: verifies `zoomIn()`, `zoomOut()`, `resetZoom()` across `[75, 80, 90, 100, 110, 125, 150]` and `increaseFontSize()`, `decreaseFontSize()`, `resetFontSize()` across `FontSizeScale.allCases`.
  - Test `testAppIconRendererProducesNonEmptyBitmapForEveryVariantAndAppliesToDock`: renders each of the 8 `CourierAppIconVariant` cases at `128×128`, asserts non-transparent center pixels and distinct palette colours per variant, and verifies `FakeAppIconApplier` records icon changes and rejects non-image custom paths.
  - Test `testRedactNamesAndPicturesProducesDeterministicPseudonymsAndAppLockBlocksMutations`: verifies `AppearancePreferences.redactedText("Alice Nguyen", kind: .name)` returns a deterministic pseudonym (`"Person #…"` / `"Chat #…"` never containing `"Alice"` or `"Nguyen"`), and verifies that mutating any `AppearancePreferences` property while `AppLockGate.shared.isLocked == true` is rejected and leaves `UserDefaults` unchanged.
- [ ] **Step 2: Implement `AppearancePreferences.swift` and `AppIconRenderer.swift`.**
- [ ] **Step 3: Run `AppearancePreferencesTests`.**

**Tests:**
```bash
bazel test //apps/desktop/courier/app:CourierCoreTests --test_filter=AppearancePreferencesTests
```

---

### Task 4: §22 Label & Space Icon Library Catalog (`CourierIconCatalog`) & Searchable `IconColorPicker`

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/CourierIconCatalog.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/LabelsModel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/IconColorPicker.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/LabelWindows.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/CourierIconCatalogTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/LabelsModelTests.swift`

**Interfaces:**

```swift
// apps/desktop/courier/app/Sources/CourierCore/CourierIconCatalog.swift
import Foundation

public enum CourierIconCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case all
    case featured
    case workAndInbox
    case peopleAndPlaces
    case travelAndOutdoors
    case mediaAndObjects
    case sportsAndLeisure
    case weatherAndNature
    case symbolsAndArrows

    public var id: String { rawValue }
    public var title: String { ... }
}

public struct CourierIconEntry: Equatable, Sendable, Identifiable {
    /// Raw inventory component name from `01-screens-and-flows.md` §22 (e.g. `"ac_unit.tsx"`, `"account_circle.tsx"`).
    public let ledgerComponent: String
    /// Native macOS SF Symbol name rendered by Courier (e.g. `"snowflake"`, `"person.crop.circle"`).
    public let sfSymbol: String
    /// Human-readable label shown in tooltips and search (e.g. `"Snowflake"`, `"Account Circle"`).
    public let title: String
    public let category: CourierIconCategory
    public let keywords: [String]
    public var id: String { ledgerComponent }
}

public enum CourierIconCatalog {
    /// All 151 §22 label and space Material-Symbol-named icon rows (`ac_unit.tsx` … `wine_bar.tsx`).
    public static let labelAndSpaceIcons: [CourierIconEntry] = [ ... ]

    /// All 25 §22 hand-drawn / UI primitive icon rows (`OutlineCheck.tsx`, `SolidMoon.tsx`, `ConfettiIcon.tsx`, `CreateLabelNudgeIcon.tsx`, etc.).
    public static let uiPrimitiveIcons: [CourierIconEntry] = [ ... ]

    /// Union of `LabelsModel.icons` (the 30 quick-pick defaults) and every `sfSymbol` in `labelAndSpaceIcons`.
    public static let allowedLabelSFSymbols: Set<String> = ...

    /// Filters `labelAndSpaceIcons` by category and free-text query across `title`, `ledgerComponent`, `sfSymbol`, and `keywords`.
    public static func search(query: String, category: CourierIconCategory = .all) -> [CourierIconEntry]
}
```

**Steps:**
- [ ] **Step 1: Write failing unit tests in `CourierIconCatalogTests.swift` and `LabelsModelTests.swift`.**
  - Test `testEverySection22MaterialSymbolRowIsMappedToValidSFSymbol`: asserts `CourierIconCatalog.labelAndSpaceIcons` contains all **151** `.tsx` icon rows from `01-screens-and-flows.md` §22 (`ac_unit.tsx` through `wine_bar.tsx`) and `CourierIconCatalog.uiPrimitiveIcons` contains all **25** §22 hand-drawn/UI icon rows (`OutlineCheck.tsx`, `OutlineChevronDown.tsx`, `OutlineChevronDownSmall.tsx`, `OutlineChevronRightSmall.tsx`, `OutlineClip.tsx`, `OutlineClock.tsx`, `OutlineCompose.tsx`, `OutlineSearch.tsx`, `OutlineSidebar.tsx`, `OutlineSpinner.tsx`, `OutlineTrash.tsx`, `SolidCircleCheck.tsx`, `SolidMoon.tsx`, `PlusIcon.tsx`, `SearchIcon.tsx`, `ErrorCircle.tsx`, `ConfettiIcon.tsx`, `icons-custom.tsx`, `icons-general.tsx`, `icons-toolbar.tsx`, `icons-networks.tsx`, `icons.tsx`, `default.tsx`, `drag_handle.tsx`, `drag_indicator.tsx`, `CreateLabelNudgeIcon.tsx`), and verifies via `NSImage(systemSymbolName:accessibilityDescription:) != nil` on macOS that every mapped `sfSymbol` resolves to a real system symbol.
  - Test `testLabelsModelAcceptsAllCatalogIconsWhilePreservingDefault30Order`: asserts `LabelsModel.icons.count == 30` in its original order (`"tag"` first), and verifies `LabelsModel.create` and `LabelsModel.update` succeed for any icon in `CourierIconCatalog.allowedLabelSFSymbols` while still rejecting empty or unknown icon strings with `EngineError.rpc(.badValue, ...)`.
  - Test `testSearchFiltersByCategoryKeywordAndMaterialName`: verifies `CourierIconCatalog.search(query: "wine")` finds `wine_bar.tsx` (`"wineglass"`), `search(query: "kayak")` or `"rowing"` finds `rowing.tsx` (`"figure.rower"`), and category filtering narrows results deterministically.
- [ ] **Step 2: Implement `CourierIconCatalog.swift` and update `LabelsModel.swift`, `IconColorPicker.swift`, and `LabelWindows.swift`.**
  - In `LabelsModel.swift`, update `create` and `update` to check `CourierIconCatalog.allowedLabelSFSymbols.contains(icon)` and update `LabelEditorWindow.fill()` in `LabelWindows.swift` to preserve any existing icon in `CourierIconCatalog.allowedLabelSFSymbols`.
  - In `IconColorPicker.swift`, keep the 12 colour circles and the default 30 quick-pick icons visible at top, and add an `"All Icons (151)…"` disclosure/search bar + category segmented control so any of the 151 §22 icons can be searched and chosen, plus `CreateLabelNudgeIcon` in `EditLabelsWindow`'s empty state (`LabelWindows.swift`).
- [ ] **Step 3: Run `CourierIconCatalogTests` and `LabelsModelTests`.**

**Tests:**
```bash
bazel test //apps/desktop/courier/app:CourierCoreTests --test_filter="CourierIconCatalogTests|LabelsModelTests"
```

---

### Task 5: Command Bar (`⌘J`) Model, Unified Command Registry & Nested Sub-Command Flows (`CommandBarModel`, `CommandSet`, `HotkeyRegistry`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/CommandBarModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/CommandSet.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/HotkeyRegistry.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/CommandBarModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/CommandSetTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/HotkeyRegistryTests.swift`

**Interfaces:**

```swift
// Additions to apps/desktop/courier/app/Sources/CourierCore/CommandSet.swift
public enum CommandCategory: String, CaseIterable, Sendable {
    case recent = "Recent"
    case chat = "Chat"
    case inbox = "Inbox & Filters"
    case message = "Messages"
    case navigation = "Spaces & Navigation"
    case appearance = "Appearance & View"
    case settings = "Settings & Accounts"
    case aiAndStubs = "AI & Tools"
}

/// A command in `CommandSet` can either run an immediate `@MainActor` action or open a nested list of sub-commands
/// (e.g. `Filter Chats ▸`, `Remind Later ▸`, `Label ▸`, `Set Theme ▸`, `Disappearing Messages ▸`).
extension CourierCommand {
    public var category: CommandCategory { ... }
    public var keywords: [String] { ... }
    public var icon: String { ... }
    public var children: [CourierCommand] { ... }
}
```

```swift
// apps/desktop/courier/app/Sources/CourierCore/CommandBarModel.swift
import Combine
import Foundation

public enum CommandBarMode: Equatable {
    case commands
    case recentChats
    case nested(parentID: String, parentTitle: String, commands: [CourierCommand])
}

public struct CommandBarRecentChatItem: Equatable, Identifiable, Sendable {
    public let roomID: String
    public let title: String
    public let networkDisplayName: String
    public let isUnread: Bool
    public var id: String { roomID }
}

@MainActor
public final class CommandBarModel: ObservableObject {
    public static let maxRecentCommands = 8

    @Published public var isPresented: Bool = false
    @Published public var query: String = ""
    @Published public var mode: CommandBarMode = .commands
    @Published public var selectedIndex: Int = 0
    @Published public private(set) var recentlyUsedCommandIDs: [String]
    @Published public var pendingConfirmation: CourierCommand?
    @Published public private(set) var lastStatusBanner: String?

    private let defaults: UserDefaults
    private var commandsProvider: @MainActor () -> [CourierCommand]
    private var recentChatsProvider: @MainActor () -> [CommandBarRecentChatItem]
    private var onSelectRecentChat: @MainActor (String) -> Void
    private var onSwitchToSearch: @MainActor (String) -> Void
    private var lockObserver: Any?

    public init(
        defaults: UserDefaults = .standard,
        lifecycle: SystemLifecycleModel? = nil,
        commandsProvider: @escaping @MainActor () -> [CourierCommand] = { [] },
        recentChatsProvider: @escaping @MainActor () -> [CommandBarRecentChatItem] = { [] },
        onSelectRecentChat: @escaping @MainActor (String) -> Void = { _ in },
        onSwitchToSearch: @escaping @MainActor (String) -> Void = { _ in }
    )

    public var visibleCommands: [CourierCommand] { ... }
    public var visibleRecentChats: [CommandBarRecentChatItem] { ... }
    public var breadcrumbTitle: String? { ... }

    public func open(mode: CommandBarMode = .commands, initialQuery: String = "")
    public func close()
    public func toggle()
    public func openRecentlyViewedChats()
    public func moveSelection(delta: Int)
    public func popNestedOrClose()
    public func executeSelected()
    public func execute(_ command: CourierCommand)
    public func confirmPendingCommand()
    public func cancelPendingConfirmation()
    public func switchToSearchPanel()
}
```

**Steps:**
- [ ] **Step 1: Write failing unit tests in `CommandBarModelTests.swift`, `CommandSetTests.swift`, and `HotkeyRegistryTests.swift`.**
  - In `CommandSetTests.swift`, add `testUnifiedCommandSetCoversEveryAcceptanceAndLedgerCommand`:
    - Verifies that `CommandSet.all(...)` contains every command promised across Milestones 4.1–4.7:
      - **4.1 (13 commands, `m4-acceptance.md:140-152`):** `Archive all chats`, `Archive all chats older than a week`, `Archive all read chats`, `Mark all chats as read`, `Next Chat`, `Show message requests`, `Toggle space bar`, `Edit spaces`, `Filter Chats` (with nested sub-commands `Filter by folder type`, `Filter by type`, `Filter by account`), `Toggle chat selection mode`.
      - **4.2 (4 commands, `m4-acceptance.md:271-274,345`):** `Search chats`, `Search messages in all chats`, `Search messages in current chat`, `Open recently viewed chats`.
      - **4.3 (7 commands, `m4-acceptance.md:511-517`):** `Send later`, `Create quick reply from draft`, `Edit`, `Forward`, `Unsend`, `Delete for me`, `Reply in thread`.
      - **4.4 (4 commands, `m4-acceptance.md:705-707`):** `Turn on incognito mode` / `Turn off incognito mode`, `Add Account`, `Account`, `Accounts` (plus `Mark as unread from last sent message` and `Reconnect`).
      - **4.5a (7 commands, `m4-acceptance.md:908-911`):** `Create new chat`, `Create new group`, `Merge chats`, `Toggle chat info`, `Search in chat info`, `Jump to date in chat`, `Show sender profile`.
      - **4.5b (4 commands, `m4-acceptance.md:1163-1164`):** `Media viewer`, `Attach file`, `Download attachments`, `Record voice note`.
      - **4.5c (2 commands, `m4-acceptance.md:1314`):** `Send GIF`, `Send Sticker`.
      - **4.6 (16 commands, `m4-acceptance.md:1498-1499`):** `Settings` / `Show settings`, `Account`, `Appearance`, `General`, `Hotkeys` / `Show keyboard shortcuts`, `Notifications`, `Quick Replies`, `Bridges`, `About`, `Help`, `Report a problem`, `Lock app`, `Open space in new window`, `Restart macOS Notification Center`, `Toggle sidebar`, `Focus Courier`.
      - **4.7 appearance, window, stub & developer commands (`ledger.tsv:436-509`):** `Commands`, `Storage`, `AI`, `Beeper Plus` / `Courier Plan`, `Integrations`, `Browser Extension`, `Mobile Apps`, `Devices`, `Secret` / `Debug Preferences`, `View subscription details / billing history / edit payment methods`, `Email feedback`, `Maximize/unmaximize`, `Zoom in`, `Zoom out`, `Reset zoom`, `Set theme to light mode`, `Set theme to dark mode`, `Set theme to system mode`, `Browse Chat Themes…`, `Customize Chat Theme…`, `Change App Icon…`, `Confetti`, `Redact names and pictures`, `Cleanup`, `Reload app`, `Relaunch app`, `Message: Talk to Type`, `Draft with AI`, `Translate Message`, plus calm informational commands for `Join a Matrix room`, `Profile`, `Logout of your Beeper account`, `Uninstall helper tool`, `Open console`, and `Open Data Explorer`.
  - In `CommandBarModelTests.swift`, test:
    - `testRankingPrefersExactAndPrefixMatchesAndBoostsRecentCommandsOnEmptyQuery`
    - `testNestedSubCommandsDrillDownAndBackspaceOnEmptyQueryPopsToParent`
    - `testOpenRecentlyViewedChatsFiltersAndSelectsRoomInInbox`
    - `testDestructiveCommandSetsPendingConfirmationBeforeRunningAction`
    - `testAppLockDismissesCommandBarAndRefusesOpenOrExecute`
  - In `HotkeyRegistryTests.swift`, test `HotkeyID.messageTalkToType` (`Message: Talk to Type`, default `⌘⇧D`) and `HotkeyID.commandBar` (`Command Bar`, default `⌘J`) + zoom shortcuts (`Zoom In` `⌘=`, `Zoom Out` `⌘-`, `Reset Zoom` `⌘0`), verifying all are no-ops while locked.
- [ ] **Step 2: Implement `CommandBarModel.swift` and expand `CommandSet.swift` and `HotkeyRegistry.swift`.**
- [ ] **Step 3: Run `CommandBarModelTests`, `CommandSetTests`, and `HotkeyRegistryTests`.**

**Tests:**
```bash
bazel test //apps/desktop/courier/app:CourierCoreTests --test_filter="CommandBarModelTests|CommandSetTests|HotkeyRegistryTests"
```

---

### Task 6: Command Bar (`⌘J`) Overlay View, `SearchPanel` Mode Switch (`Commands ⌘J`) & Menu Bar Wiring

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/CommandBarOverlay.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SearchPanel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SearchFilterBar.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/InboxCommands.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MenuBar.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/DockAndTrayModel.swift`

**Interfaces:**

```swift
// apps/desktop/courier/app/Sources/Courier/CommandBarOverlay.swift
import AppKit
import CourierCore
import SwiftUI

public struct CommandBarOverlay: View {
    @ObservedObject public var model: CommandBarModel
    @ObservedObject public var hotkeys: HotkeyRegistry
    public var colorScheme: ColorScheme? = nil

    public init(
        model: CommandBarModel,
        hotkeys: HotkeyRegistry,
        colorScheme: ColorScheme? = nil
    )
}

public struct CommandBarFooterView: View {
    public let isNested: Bool
    public let isRecentChatsMode: Bool
    public let onSwitchToSearch: () -> Void
}

public struct ConfettiOverlayView: View {
    public let triggerCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}
```

**Steps:**
- [ ] **Step 1: Implement `CommandBarOverlay.swift` (`CommandBarOverlay`, `CommandBarRowView`, `CommandBarRecentChatRowView`, `CommandBarFooterView`, `ConfettiOverlayView`).**
  - Renders the top-centered command palette (`width: 580, maxHeight: 440`) with:
    - Search bar icon (`command`), optional breadcrumb pill (`model.breadcrumbTitle`), `@FocusState` text field (`"Type a command or search…"` in command mode, `"Filter recently viewed chats…"` in `.recentChats` mode), and trailing `"Search ⌘K"` pill button that calls `model.switchToSearchPanel()`.
    - Keyboard handlers: `.onKeyPress(.upArrow)` / `⌃P`, `.onKeyPress(.downArrow)` / `⌃N`, `.onKeyPress(.return)` (`model.executeSelected()`), `.onKeyPress(.delete)` when `model.query.isEmpty` (`model.popNestedOrClose()`), and `.onKeyPress(.escape)` (`model.popNestedOrClose()`).
    - Grouped command rows with SF Symbol icon, title, subtitle, disabled reason badge when `!command.enabled`, nested chevron (`chevron.right`) when `!command.children.isEmpty`, and shortcut keycaps from `HotkeyRegistry`.
    - Confirmation alert bound to `model.pendingConfirmation` (`Confirm` dialog title, message, destructive button, and Cancel).
    - `ConfettiOverlayView` rendered over `MainWindow` when `appearancePreferences.confettiTriggerCount` increments (drawing 32 deterministic coloured vector confetti shapes when `!reduceMotion`, or a static celebration toast when `reduceMotion` is on).
- [ ] **Step 2: Wire the `"Commands ⌘J"` switch inside `SearchPanel.swift` (`m4-acceptance.md:345`).**
  - Add `var onOpenCommandBar: ((String) -> Void)? = nil` to `SearchPanel`.
  - In `SearchPanel.bar`, add a `"Commands ⌘J"` button next to the close button (with `.help(String(localized: "Switch to Command Bar (⌘J)"))`) that closes `SearchPanel` and opens `CommandBarModel` (preserving any typed query), and also switch automatically if the person types `>` as the leading character in `SearchPanel`.
- [ ] **Step 3: Wire `⌘J` (`Courier ▸ Command Bar…`), `Focus Courier and Command Bar` (`⌘⇧Space`), and `View ▸ Zoom In / Zoom Out / Actual Size` in `InboxCommands.swift`, `MenuBar.swift`, `DockAndTrayModel.swift`, and `MainWindow.swift`.**
- [ ] **Step 4: Build and run `CourierCoreTests` and `Courier` target.**

**Tests:**
```bash
bazel build --config=macos-app //apps/desktop/courier/app:Courier
bazel test //apps/desktop/courier/app:CourierCoreTests
```

---

### Task 7: Appearance Settings Pane, App Icon Picker, Chat Theme Window & Chat Theme Browser (`GeneralSettingsPane.swift`, `AppIconPickerView.swift`, `ChatThemeWindow.swift`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/AppIconPickerView.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/ChatThemeWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/GeneralSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SettingsWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/SettingsSearchModel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/LabelWindows.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/App.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/InboxRow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatInfoPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatContextMenu.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/DetachedWindows.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/SettingsSearchModelTests.swift`

**Interfaces:**

```swift
// apps/desktop/courier/app/Sources/Courier/AppIconPickerView.swift
import CourierCore
import SwiftUI

/// `AppIconPrefsSubView.tsx` — grid of Courier's 8 clean-room vector app icons plus custom PNG/JPG/ICNS upload.
public struct AppIconPickerView: View {
    @ObservedObject public var appearance: AppearancePreferences
    public init(appearance: AppearancePreferences)
}
```

```swift
// apps/desktop/courier/app/Sources/Courier/ChatThemeWindow.swift
import CourierCore
import SwiftUI

/// `ChatThemeWindow.tsx` — per-chat theme, bubble colour, and wallpaper editor sheet/window.
public struct ChatThemeWindow: View {
    public let roomID: String
    public let chatTitle: String
    @ObservedObject public var appearance: AppearancePreferences
    public var onDismiss: () -> Void = {}
}

/// `ChatThemeBrowserWindow.tsx` — standalone gallery browser of all 8 Courier theme presets and 8 procedural wallpapers
/// with a live conversation preview, "Use as Default Theme", and optional "Apply to <Current Chat>".
public struct ChatThemeBrowserWindow: View {
    @ObservedObject public var appearance: AppearancePreferences
    public var activeRoomID: String? = nil
    public var activeChatTitle: String? = nil
    public var onDismiss: () -> Void = {}
}

/// Procedural vector wallpaper canvas rendered behind ConversationView and NoChatSelected (`EmptyStateBackground.tsx`,
/// `EmptyStateBackgroundThumbnail.tsx`).
public struct ChatWallpaperCanvasView: View {
    public let preset: CourierWallpaperPreset
    public let customImagePath: String?
    public let opacity: Double
    public let blur: Bool
    public let reduceTransparency: Bool
}

/// Optional empty-state unread summary cards (`FeaturedHoneycombCard.tsx`, `UnreadThreadCard.tsx`) shown in `NoChatSelected`
/// when `appearance.showHoneycombCards` is enabled.
public struct EmptyStateUnreadCardsView: View {
    public let unreadRows: [CourierCore.InboxRow]
    public let onSelectRoom: (String) -> Void
}
```

**Steps:**
- [ ] **Step 1: Write failing unit tests in `SettingsSearchModelTests.swift` for all new Appearance, Storage, AI, Plan, and Integrations setting items.**
  - Assert that `SettingsSearchCatalog.allItems` includes searchable entries with matching highlight anchors for:
    - `appearance.themeMode` (`"Theme"`, keywords `["light", "dark", "system", "appearance"]`)
    - `appearance.themePreset` (`"Colour theme"`, `"Browse Chat Themes…"`)
    - `appearance.wallpaper` (`"Chat wallpaper"`, `"Empty-state background"`)
    - `appearance.appIcon` (`"App Icon"`, `AppIconPrefsSubView.tsx`)
    - `appearance.fontSize` (`"Font size"`, `setting:appearance Font size`)
    - `appearance.zoomLevel` (`"Zoom level"`, `Zoom In`, `Zoom Out`, `Reset Zoom`)
    - `appearance.reduceTransparency` (`"Reduce transparency"`, `setting:appearance Reduce transparency`)
    - `appearance.enableMessageAnimations` (`"Enable message animations"`, `setting:appearance Enable message animations`)
    - `appearance.balanceMessageText` (`"Balance message text"`, `setting:appearance Balance message text`)
    - `appearance.usePointerCursor` (`"Use pointer cursor for interactive elements"`, `setting:appearance Use pointer cursor for interactive elements`)
    - `appearance.showFeedbackWidget` (`"Show feedback widget"`, `setting:appearance Show feedback widget`)
    - `appearance.redactNamesAndPictures` (`"Redact names and pictures"`, `command Redact names and pictures`)
    - `appearance.customCSS` (`"Custom CSS"`, `ThemeFileLoader`)
- [ ] **Step 2: Implement `AppIconPickerView.swift` and `ChatThemeWindow.swift` (`ChatThemeWindow`, `ChatThemeBrowserWindow`, `ChatWallpaperCanvasView`, `EmptyStateUnreadCardsView`).**
  - Add `WindowID.chatTheme = "chat-theme"` and `WindowID.chatThemeBrowser = "chat-theme-browser"` in `LabelWindows.swift` and wire scenes in `App.swift` wrapped in `LockableWindowContent(lifecycle:)`.
  - Add `"Chat Theme…"` to `ChatContextMenu.swift` and `ChatInfoPane.swift`.
- [ ] **Step 3: Expand `AppearanceSettingsPane` in `GeneralSettingsPane.swift` and wire `AppearancePreferences` into `MainWindow.swift`, `InboxRow.swift`, `ConversationView.swift`, `MessageBubble.swift`, `ComposerView.swift`, and `DetachedWindows.swift`.**
  - Apply `appearance.themeMode` (`.preferredColorScheme`), `appearance.effectiveTheme(for: conversation.roomID)` (outgoing/incoming bubble fills, accent tint, and `ChatWallpaperCanvasView`), `appearance.fontSizeScale` (message bubble and inbox preview fonts), `appearance.zoomPercent` (scale effect / layout multiplier), and `appearance.redactNamesAndPictures` (redacting chat titles, sender names, and blurring avatars when enabled).
- [ ] **Step 4: Run `SettingsSearchModelTests` and `CourierCoreTests`.**

**Tests:**
```bash
bazel test //apps/desktop/courier/app:CourierCoreTests --test_filter="SettingsSearchModelTests|AppearancePreferencesTests"
```

---

### Task 8: Storage Management Settings Pane (`StorageSettingsPane.swift`, `StorageModel.swift`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/StorageModel.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/StorageSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/SettingsSearchModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/DockAndTrayModel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SettingsWindow.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/StorageModelTests.swift`

**Interfaces:**

```swift
// apps/desktop/courier/app/Sources/CourierCore/StorageModel.swift
import Combine
import Foundation

public enum StorageCleanupAgeChoice: Int, CaseIterable, Codable, Sendable, Identifiable {
    case oneWeek = 7
    case oneMonth = 30
    case threeMonths = 90
    case oneYear = 365
    case allTime = 0

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .oneWeek: String(localized: "Delete media older than 1 week")
        case .oneMonth: String(localized: "Delete media older than 1 month")
        case .threeMonths: String(localized: "Delete media older than 3 months")
        case .oneYear: String(localized: "Delete media older than 1 year")
        case .allTime: String(localized: "Delete Media…")
        }
    }
    public var olderThanMS: Int64? {
        rawValue > 0 ? Int64(rawValue) * 86_400_000 : nil
    }
}

@MainActor
public final class StorageModel: ObservableObject {
    @Published public private(set) var usage: StorageUsageResult?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isCleaning: Bool = false
    @Published public var selectedAgeChoice: StorageCleanupAgeChoice = .oneMonth
    @Published public var roomFilterQuery: String = ""
    @Published public private(set) var lastStatusMessage: String?
    @Published public private(set) var lastErrorMessage: String?

    public init(appModel: AppModel)

    public var filteredRooms: [RoomStorageUsage] { ... }
    public func refresh() async
    public func clearMedia(olderThan choice: StorageCleanupAgeChoice) async
    public func clearMedia(forRoomID roomID: String) async
    public func clearAllCache() async
    public static func formatBytes(_ bytes: Int64) -> String
}
```

```swift
// apps/desktop/courier/app/Sources/Courier/StorageSettingsPane.swift
import CourierCore
import SwiftUI

/// `StoragePrefsSubView.tsx`, `StorageOverviewChart.tsx`, and `StorageByRoomList.tsx`.
public struct StorageSettingsPane: View {
    @ObservedObject public var model: StorageModel
    public init(model: StorageModel)
}

public struct StorageOverviewChartView: View {
    public let usage: StorageUsageResult
}

public struct StorageByRoomListView: View {
    public let rooms: [RoomStorageUsage]
    public let isCleaning: Bool
    public let onClearRoom: (RoomStorageUsage) -> Void
}
```

**Steps:**
- [ ] **Step 1: Write failing unit tests in `StorageModelTests.swift`.**
  - Test `testRefreshLoadsStorageUsageAndFiltersRoomsByQuery`: connects `StorageModel` to `TestEngineServer`, verifies `refresh()` populates `usage` (`imagesBytes`, `videosBytes`, `audioBytes`, `filesBytes`, `stickersBytes`, `databaseBytes`, `cacheBytes`, `totalBytes`, and `rooms`), and verifies `roomFilterQuery` filters `filteredRooms` case-insensitively by chat name or network.
  - Test `testClearMediaByAgeAndByRoomCallsStorageCleanupAndRefreshes`: calls `clearMedia(olderThan: .oneMonth)`, `clearMedia(forRoomID: "!wa:1")`, and `clearAllCache()`, asserting `storage.cleanup` receives the exact `older_than_ms` / `room_id` parameters, updates `lastStatusMessage` (`"Cleared 14.2 MB of cached media"`), and automatically re-runs `storage.usage`.
  - Test `testStorageActionsAreRefusedWhileAppLocked`: locks `SystemLifecycleModel` and verifies `refresh()`, `clearMedia(olderThan:)`, and `clearMedia(forRoomID:)` are blocked by `AppLockGate`.
- [ ] **Step 2: Implement `StorageModel.swift` and `StorageSettingsPane.swift`, and add `.storage` (`"Storage"`, icon `"internaldrive"`) to `SettingsPaneID` in `SettingsSearchModel.swift`, `SettingsSection` in `DockAndTrayModel.swift`, and `SettingsWindow.swift`.**
- [ ] **Step 3: Run `StorageModelTests` and `SettingsSearchModelTests`.**

**Tests:**
```bash
bazel test //apps/desktop/courier/app:CourierCoreTests --test_filter="StorageModelTests|SettingsSearchModelTests"
```

---

### Task 9: AI, Plan & Integrations Stub Surfaces (`AISettingsPane.swift`, `AIPane.swift`, `PlusSettingsPane.swift`, `ComposerView.swift`, `MessageBubble.swift`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/AISettingsPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/AIPane.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/PlusSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/SettingsWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/SettingsSearchModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ConversationModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/MessageMenu.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/MessageActionsModel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageMenu.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ProblemReportSheet.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ComposerModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/MessageActionsModelTests.swift`

**Interfaces:**

```swift
// apps/desktop/courier/app/Sources/Courier/AISettingsPane.swift
import CourierCore
import SwiftUI

/// `Settings ▸ AI` (`01` §13, `02` §1.3): covers `setting:ai Translation Languages`, `setting:ai Arabic`,
/// `setting:ai Use OpenAI's Whisper model for Talk to Type and transcribing`, `setting:ai Mention an AI to get answers and help in chat`,
/// and `createSlashCommandTriggerSettings.tsx`, backed by `AIPreferences` and `AIProvider`.
public struct AISettingsPane: View {
    @ObservedObject public var preferences: AIPreferences
    public let provider: any AIProvider
    public init(preferences: AIPreferences, provider: any AIProvider = UnavailableAIProvider())
}
```

```swift
// apps/desktop/courier/app/Sources/Courier/AIPane.swift
import CourierCore
import SwiftUI

/// `AIPane.tsx`, `AIMessageContent.tsx`, `AIMessageFooterActions.tsx`, `AIMessageParts.tsx`,
/// `AIModelButton.tsx`, `AISpinnerVerb.tsx`, `AIToolCallsPanel.tsx` (`01` §13).
public struct AIPane: View {
    public let chatTitle: String
    @ObservedObject public var preferences: AIPreferences
    public let provider: any AIProvider
    public var onClose: () -> Void = {}
}

/// `MessageTranslations.tsx` and `MessageTranslationRow.tsx` (`01` §8, §13): inline translation row shown under a message bubble.
public struct MessageTranslationRowView: View {
    public let targetLanguage: String
    public let disposition: AIProviderDisposition
    public var onDismiss: () -> Void = {}
}
```

```swift
// apps/desktop/courier/app/Sources/Courier/PlusSettingsPane.swift
import CourierCore
import SwiftUI

/// `Settings ▸ Courier Plan` & `Settings ▸ Integrations`: covers `setting:beeper-plus Go Unlimited`,
/// `PlusPill.tsx`, `FreebieNudge.tsx`, `SubscriptionExpiryBanners.tsx`, `BrowserExtPrefsSubView.tsx`,
/// `MobileAppsPrefsSubView.tsx`, `SecretPrefsSubView.tsx`, `DebugPreferencesIndex.tsx`, and `setting:integrations *`.
public struct PlusSettingsPane: View {
    public let entitlement: any EntitlementProvider
    public init(entitlement: any EntitlementProvider = AlwaysEntitled())
}

public struct PlusPillView: View {
    public let title: String
    public let isUnlimited: Bool
}

public struct FreebieNudgeView: View {
    public let text: String
    public var onLearnMore: () -> Void = {}
}

public struct SubscriptionExpiryBannerView: View {
    public let state: SubscriptionExpiryBannerState
    public var onAction: () -> Void = {}
}

public struct IntegrationsSettingsPane: View {
    public init()
}
```

**Steps:**
- [ ] **Step 1: Write failing unit tests in `ComposerModelTests.swift` and `MessageActionsModelTests.swift`.**
  - Test `testTalkToTypeDraftWithAIAndSlashCommandsShowCalmStubNoticeWithoutLosingDraft`:
    - Sets `composer.text = "Hello team"`, triggers `composer.triggerTalkToType()`, `composer.draftWithAI(tone: .moreConcise)`, and slash commands `/ai`, `/translate`, `/summarize`, `/draft`.
    - Verifies `composer.text` remains `"Hello team"` (draft is never lost or sent) and `composer.notice` displays the calm `UnavailableAIProvider` message (`"Talk to Type isn’t available yet in Courier."`, `"Drafting with AI isn’t available yet in Courier."`).
  - Test `testTranslateMessageStoresCalmUnavailableTranslationOnEvent`:
    - Calls `messageActions.translateMessage(eventID: "$m1", targetLanguage: "Spanish")` and verifies `messageActions.translations["$m1"] == .unavailable(reason: "Message translation isn’t available yet in Courier.")` and `messageActions.dismissTranslation(eventID: "$m1")` clears it.
- [ ] **Step 2: Implement `AISettingsPane.swift`, `AIPane.swift`, and `PlusSettingsPane.swift` (`PlusSettingsPane`, `PlusPillView`, `FreebieNudgeView`, `SubscriptionExpiryBannerView`, `IntegrationsSettingsPane`).**
  - Add `.ai` (`"AI"`, icon `"sparkles"`), `.plan` (`"Courier Plan"`, icon `"Checkmark.seal"` / `"star.circle"`), and `.integrations` (`"Integrations"`, icon `"puzzlepiece.extension"`) to `SettingsPaneID` in `SettingsSearchModel.swift` and wire them in `SettingsWindow.swift`.
  - Wire `"Translate"` into `MessageMenu.swift` (`CourierCore` and `Courier`) and render `MessageTranslationRowView` beneath the message in `MessageBubble.swift` when a translation state exists for that `eventID`.
  - Wire `Talk to Type` (`⌘⇧D`), `Draft with AI`, and `/` slash command suggestions into `ComposerModel.swift` and `ComposerView.swift`.
  - Update `ProblemReportSheet.swift` to show the `ReportUploader` calm status / `"Upload Report (Not available yet)"` control alongside `"Save Problem Report…"`.
- [ ] **Step 3: Run `ComposerModelTests`, `MessageActionsModelTests`, and `SettingsSearchModelTests`.**

**Tests:**
```bash
bazel test //apps/desktop/courier/app:CourierCoreTests --test_filter="ComposerModelTests|MessageActionsModelTests|SettingsSearchModelTests|ProviderStubsTests"
```

---

### Task 10: Snapshot Matrix (`CourierViewTests`), End-to-End Integration Tests & Acceptance Documentation (`m4-acceptance.md`, `04-coverage-ledger.md`)

**Files:**
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`
- Modify: `apps/desktop/courier/docs/m4-acceptance.md`
- Modify: `docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/04-coverage-ledger.md`

**Steps:**
- [ ] **Step 1: Add light and dark PNG snapshot tests in `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift` for every Milestone 4.7 view surface.**
  - `testCommandBarOverlaySnapshotsLightAndDark`:
    - Snapshots `CommandBarOverlay` in light and dark mode for: (a) home view with recent commands and categories, (b) filtered query `"archive"` showing matching commands and shortcuts, (c) nested `"Filter Chats ▸"` sub-commands with breadcrumb, (d) `"Open recently viewed chats"` mode, and (e) `SearchPanel` header showing the `"Commands ⌘J"` switch pill.
  - `testAppearanceSettingsAndAppIconPickerSnapshotsLightAndDark`:
    - Snapshots `AppearanceSettingsPane` (theme presets, wallpapers, font size & zoom controls, redact toggle, and `ThemeFileLoader` custom CSS calm stub) and `AppIconPickerView` (all 8 original vector app icons) in light and dark mode.
  - `testChatThemeWindowAndBrowserSnapshotsLightAndDark`:
    - Snapshots `ChatThemeWindow` (per-chat override sheet) and `ChatThemeBrowserWindow` (preset and wallpaper gallery with live conversation preview) in light and dark mode, plus conversation bubbles with `Topographic Lines` wallpaper, `Midnight Indigo` preset, scaled `Extra Large` font size, and `"Redact names and pictures"` mode enabled.
  - `testStorageSettingsPaneSnapshotsLightAndDark`:
    - Snapshots `StorageSettingsPane` (`StorageOverviewChartView` and `StorageByRoomListView` with seeded room storage data) in light and dark mode.
  - `testAISettingsAIPaneTranslationAndPlusSettingsSnapshotsLightAndDark`:
    - Snapshots `AISettingsPane`, `AIPane`, `MessageTranslationRowView`, `PlusSettingsPane` (both `AlwaysEntitled` and `NoPlan` `"Available with a plan"` states with `PlusPillView`, `FreebieNudgeView`, and `SubscriptionExpiryBannerView`), and `IntegrationsSettingsPane` in light and dark mode.
  - `testSection22IconCatalogPickerAndEmptyStateCardsSnapshotsLightAndDark`:
    - Snapshots `IconColorPicker` with the §22 search bar and category filter open, and `NoChatSelected` with `EmptyStateBackground` and `EmptyStateUnreadCardsView` (`FeaturedHoneycombCard` / `UnreadThreadCard`).
- [ ] **Step 2: Update `apps/desktop/courier/docs/m4-acceptance.md` and `docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/04-coverage-ledger.md`.**
  - Add `## Part 4.7: appearance, command bar and stubs` to `apps/desktop/courier/docs/m4-acceptance.md` documenting:
    - What leaves this Mac (nothing — every 4.7 feature is 100% local on this Mac) and what stays on this Mac;
    - Out-of-the-box defaults (`Theme: System`, `Colour theme: Classic Teal`, `Wallpaper: None`, `Font size: Default (100%)`, `Zoom: 100%`, `Reduce transparency: off`, `Redact names and pictures: off`, `App Icon: Classic Teal`, `AI features: unavailable stub`);
    - The 5 things to check first (`⌘J` Command Bar & `SearchPanel` switch, Themes/Wallpapers/Per-Chat Themes/App Icons, Storage breakdown & safe media cleanup, the 5 Provider Stubs making zero network calls, and `AppLockGate` blocking every new surface while locked);
    - Every key, setting, menu item, component, and command delivered in 4.7.
  - Update `04-coverage-ledger.md` summary notes to reflect that Milestone 4 (4.1–4.7) is complete.
- [ ] **Step 3: Run the full Courier Go, Rust, and Swift test suites.**

**Tests:**
```bash
bazel test //apps/desktop/courier/engine/... //apps/desktop/courier/gchat/... //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests
```

---

## Owner's By-Hand Day (End-to-End Verification Checklist)

1. **Build and Install:**
   - Run `bazel run --config=macos-app //apps/desktop/courier/app:install -- --allow-missing` and launch `/Applications/Courier.app`.
2. **Command Bar (`⌘J`) & `SearchPanel` Switch:**
   - Press `⌘J` (and try `Courier ▸ Command Bar…` and global `⌘⇧Space`): verify the Command Bar opens at the top of the window with your recent commands and all categories (`Chat`, `Inbox & Filters`, `Messages`, `Spaces & Navigation`, `Appearance & View`, `Settings & Accounts`, `AI & Tools`).
   - Type `filter`, press `Return` on `Filter Chats`, and verify it drills into `Filter by folder type`, `Filter by type`, `Filter by account`, `Unread`, `DMs`, `Groups`, etc.; press `⌫` on an empty query to pop back.
   - Run `Open recently viewed chats` from `⌘J` and verify your recent chats list appears and selecting one opens that chat.
   - Press `⌘K` to open Search, click `"Commands ⌘J"` in the top-right of the search bar (or type `>`), and verify it switches smoothly into the Command Bar.
3. **Appearance, Wallpapers, Per-Chat Themes, App Icons, Font Size, Zoom & Redact Mode:**
   - Open `Settings ▸ Appearance` (`⌘,`): switch between `System`, `Light`, and `Dark`, try each of the 8 Courier theme presets and 8 procedural wallpapers, adjust wallpaper opacity and blur, and click `"Browse Chat Themes…"` to preview themes side by side.
   - Right-click a test chat ▸ `Chat Theme…`, pick a custom preset, bubble colour, and wallpaper just for that chat, and verify switching between that chat and another chat changes the conversation theme live.
   - In `Settings ▸ Appearance ▸ App Icon`, click through the 8 original Courier icons and verify the macOS Dock icon updates immediately, then click `"Reset to Default Icon"`.
   - Change `Font size` from `Extra Small` to `Extra Large`, press `⌘+`, `⌘-`, and `⌘0` (`View ▸ Zoom In / Zoom Out / Actual Size`), toggle `"Redact names and pictures"` on and off, and run `"Confetti"` from `⌘J`.
4. **§22 Label & Space Icon Picker:**
   - Open `Edit Labels…` ▸ `New Label…`, search in `"Search icons…"` for `"snowflake"`, `"kayak"`, `"coffee"`, or `"wine"`, pick an icon and colour, and save.
5. **Storage Management (`Settings ▸ Storage`):**
   - Open `Settings ▸ Storage` (or run `Storage` / `Delete Media…` from `⌘J`): inspect the category bar chart (`Images`, `Videos`, `Audio`, `Other Files`, `Stickers`, `Messages & Database`) and the per-chat storage list; run `"Delete media in this chat"` for one test chat and verify message text and history stay intact while media tiles show `"Removed to free up space"`.
6. **The Five Provider Stubs (`AIProvider`, `GIFProvider`, `EntitlementProvider`, `ReportUploader`, `ThemeFileLoader`):**
   - Open `Settings ▸ AI`, the right-hand `AIPane`, `Settings ▸ Courier Plan`, `Settings ▸ Integrations`, `Custom CSS` in `Settings ▸ Appearance`, `"Report a Problem…"` (`⌘⇧P`), `⌘⇧D` (`Message: Talk to Type`), and `Translate` on a message: verify every screen shows a calm `"not available yet"` explanation in Courier's words with zero errors and zero network activity.

---

## Ledger & Acceptance Coverage Table (Every 4.7 Row Mapped to Tasks 1–10)

| Source (`m4-acceptance.md` / `ledger.tsv`) | Item / Ledger Row | Assigned Task(s) |
|---|---|---|
| `m4-acceptance.md:138-153` (`ledger.tsv:440-446,450,454-455,461-464,499`) | 4.1 commands shown in `⌘J`: `Archive all chats`, `Archive all chats older than a week`, `Archive all read chats`, `Mark all chats as read`, `Next Chat`, `Show message requests`, `Toggle space bar`, `Edit spaces`, `Filter Chats`, `Filter by folder type`, `Filter by type`, `Filter by account`, `Toggle chat selection mode` | Tasks 5, 6, 10 |
| `m4-acceptance.md:196` (`01-screens-and-flows.md` §22, `ledger.tsv:265-435`) | All 151 §22 Material-Symbol-named icon-library rows (`ac_unit.tsx` … `wine_bar.tsx`) + 25 §22 UI/hand-drawn icon rows (`OutlineCheck.tsx`, `SolidMoon.tsx`, `ConfettiIcon.tsx`, `CreateLabelNudgeIcon.tsx`, etc.) | Tasks 4, 10 |
| `m4-acceptance.md:269-274` (`ledger.tsv:437,449`) | 4.2 commands shown in `⌘J`: `Search chats`, `Search messages in all chats`, `Search messages in current chat` | Tasks 5, 6, 10 |
| `m4-acceptance.md:345` (`ledger.tsv:439,445,215,216`) | `"Open recently viewed chats"`, `Commands` (`⌘J`) switch inside `SearchPanel`, `SelectMessageCommand.tsx`, `SelectRecentSearchCommand.tsx` | Tasks 5, 6, 10 |
| `m4-acceptance.md:509-518` (`ledger.tsv:560,552,553`) | 4.3 commands shown in `⌘J`: `Send later`, `Create quick reply from draft`, `Edit`, `Forward`, `Unsend`, `Delete for me`, `Reply in thread` | Tasks 5, 6, 10 |
| `m4-acceptance.md:592` (`ledger.tsv:5-11,69,124,164-165,190-191,234,296,563,567-570,604`) | `Talk to Type`, `Draft with AI`, `Translate` (`MessageTranslations.tsx`, `MessageTranslationRow.tsx`), slash commands (`createSlashCommandTriggerSettings.tsx`), trial nudges (`FreebieNudge.tsx`), subscription screens behind `"Available with a plan"` (`PlusPill.tsx`, `CheckboxPlus.tsx`, `SubscriptionExpiryBanners.tsx`, `setting:beeper-plus Go Unlimited`) | Tasks 2, 5, 9, 10 |
| `m4-acceptance.md:632,703-707` (`ledger.tsv:466-468,487`) | 4.4 commands shown in `⌘J`: `Turn on incognito mode` / `Turn off incognito mode`, `Add Account`, `Account`, `Accounts` | Tasks 5, 6, 10 |
| `m4-acceptance.md:906-911` (`ledger.tsv:438,446,447,520,527`) | 4.5a commands shown in `⌘J`: `Create new chat`, `Create new group`, `Merge chats`, `Toggle chat info`, `Search in chat info`, `Jump to date in chat`, `Show sender profile` | Tasks 5, 6, 10 |
| `m4-acceptance.md:972,1205,1320` (`ledger.tsv:129`) | `component` `GifPicker.tsx`: online GIF search provider stub (`GIFProvider` / `StubGIFProvider`) tracked alongside the 5 external service stubs | Tasks 2, 10 |
| `m4-acceptance.md:1008-1009,1217-1218,1344-1345,1537-1538` (`ledger.tsv:66-67`) | `component` `ChatThemeBrowserWindow.tsx` & `component` `ChatThemeWindow.tsx` (Appearance, wallpapers, and per-chat themes) | Tasks 3, 7, 10 |
| `m4-acceptance.md:1013,1222,1349,1541` (`ledger.tsv:563`) | `hotkey` `Message: Talk to Type` (`AIProvider` dictation stub) | Tasks 2, 5, 9, 10 |
| `m4-acceptance.md:1015,1224,1351,1542` (`ledger.tsv:569`) | `setting:ai` `Use OpenAI's Whisper model for Talk to Type and transcribing` (`AIProvider` voice-note transcription stub) | Tasks 2, 9, 10 |
| `m4-acceptance.md:1161-1164` (`ledger.tsv:489,511,551,558`) | 4.5b commands shown in `⌘J`: `Media viewer`, `Attach file`, `Download attachments`, `Record voice note` | Tasks 5, 6, 10 |
| `m4-acceptance.md:1312-1314` (`ledger.tsv:559,562`) | 4.5c commands shown in `⌘J`: `Send GIF`, `Send Sticker` | Tasks 5, 6, 10 |
| `m4-acceptance.md:1496-1500` (`ledger.tsv:451-453,459-460,465-486,490,506,528,533,658`) | 4.6 commands shown in `⌘J` + `menu:Beeper Command Bar…` + `hotkey Command Bar` (`⌘J`) + `hotkey Focus App and Command Bar`: `Settings`, `Account`, `Appearance`, `General`, `Hotkeys`, `Notifications`, `Quick Replies`, `Bridges`, `About`, `Help`, `Show keyboard shortcuts`, `Report a problem`, `Lock app`, `Open space in new window`, `Restart macOS Notification Center` | Tasks 5, 6, 10 |
| `ledger.tsv:23,77,109-110,118,260,491-505,539,549-550,573,583-584,592,601,603` | Appearance, App Icons, Empty-State & Zoom rows: `AppIconPrefsSubView.tsx`, `ConfettiIcon.tsx`, `EmptyStateBackground.tsx`, `EmptyStateBackgroundThumbnail.tsx`, `FeaturedHoneycombCard.tsx`, `UnreadThreadCard.tsx`, `Zoom in`, `Zoom out`, `Reset zoom`, `Set theme to light mode`, `Set theme to dark mode`, `Confetti`, `Redact names and pictures`, `Reduce transparency`, `Enable message animations`, `Balance message text`, `Show feedback widget`, `Use pointer cursor for interactive elements`, `Font size`, Custom CSS (`ThemeFileLoader`) | Tasks 2, 3, 5, 6, 7, 10 |
| `ledger.tsv:230-232,478,505` (`2026-10-25-courier-m4-6-settings-bridges.md:11`) | Storage management: `StoragePrefsSubView.tsx`, `StorageOverviewChart.tsx`, `StorageByRoomList.tsx`, `command Storage`, `command Cleanup`, `storage.usage`, `storage.cleanup` | Tasks 1, 5, 8, 10 |
| `m4-acceptance.md:1534-1544` (explicitly marked `"not planned in iteration 1"`) | 7 non-Courier / bridge-architecture rows (`command Join a Matrix room`, `command Profile`, `component ChangeEmailBrowserWindow.tsx`, `component DeleteAccountModal.tsx`, `component DeleteAccountPrompt.tsx`, `setting:general Show Telegram Topics as separate spaces`, `setting:general Show WhatsApp Communities as separate spaces`) | Documented as non-applicable in iteration 1 in `m4-acceptance.md` (with calm informational entries in `CommandSet` for command-bar searchability in Task 5) |
