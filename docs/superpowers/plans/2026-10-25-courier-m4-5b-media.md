# Courier Milestone 4.5b — Rich Media Playback, Capture, Previews, and Media Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Courier rich local media playback, capture, previews, and browsing across all five networks: inline images with BlurHash placeholders and gallery grids, view-once media, inline video and Picture-in-Picture, inline voice notes (`0.5×–2×` speed, waveform scrubber, continuous playback, played state) and persistent floating audio bar, microphone voice-note recording (`⌘⇧A`), inline paged PDFs and rich file cards with drag-and-drop and download preferences (`⌘O`, `⌘D`), inline location map cards, incoming and outgoing link previews with privacy-gated external embeds, the full-window attachment lightbox (`AttachmentCarousel`), and the standalone Media Viewer window (`MediaViewerBrowserWindow`) — plus the three review follow-ups carried from Milestone 4.5a.

**Architecture:** Courier's Go engine (`apps/desktop/courier/engine/`) stores every incoming and outgoing media blob in content-addressed local storage (`<datadir>/media/<sha256[:2]>/<sha256>`). In 4.5b, schema migration 9 and protocol v7 extend `events` and `room.features` with rich media metadata (`blurhash`, `thumbnail_path`, `duration_ms`, `waveform`, `is_gif`, `is_animated`, `view_once`, `geo_uri`, `link_previews`, `played`, and per-kind `FileFeatures` capability limits read directly from each bridge's `GetCapabilities`), add local played-state tracking (`media_played` table + `message.markPlayed`), and add `message.sendVoice` (with optional `ffmpeg` OGG/Opus or M4A/AAC conversion per bridge capability) and `message.sendLocation`. On the Swift side (`apps/desktop/courier/app/`), `CourierCore` adds models for audio/voice playback, microphone recording (`AVAudioEngine` / `AVAudioRecorder`), attachment downloads, gallery grouping, link previews, and the Media Viewer, while `Courier` adds the SwiftUI / AppKit views (`AVKit`, `PDFKit`, `MapKit`, `QuickLookUI`) verified by light and dark PNG snapshot tests.

**Tech Stack:** Go 1.26 (`modernc.org/sqlite`, `maunium.net/go/mautrix` v0.31.0 `bridgev2`, standard `image/*` + `golang.org/x/image/webp`), Swift 6 / SwiftUI on macOS 14 (`AVFoundation`, `AVKit`, `PDFKit`, `MapKit`, `QuickLookUI`), Bazel (`rules_go`, `rules_swift`, `rules_apple`).

---

## Scope & Split (4.5b vs 4.5c)

The 45 rows carried under "Carried to Milestone 4.5b" in `docs/superpowers/plans/2026-10-24-courier-m4-5-people-and-media.md` plus the 3 review follow-ups from 4.5a would take 19 tasks in a single plan. To stay within 13 focused tasks, Milestone 4.5's media half splits into:

1. **Milestone 4.5b — Rich Media Playback, Capture, Previews, and Media Viewer (this plan, 13 tasks, 35 inventory rows + 3 review follow-ups from 4.5a):**
   - Task 1 resolves all three 4.5a review follow-ups (single `AppModel.mergedChats` owner, test/lint guard against raw `selectedRoomID ==` and sending `"merge:…"` to the engine, and removing the 50 ms sleep in `SearchModelTests.swift`).
   - Tasks 2–4 add protocol v7, migration 9, media metadata extraction (dimensions, BlurHash, video posters, audio waveforms, view-once, link previews), per-kind bridge `FileFeatures`, `message.sendVoice`, `message.sendLocation`, and notification media attachments.
   - Tasks 5–11 build inline images + gallery grids + view-once viewer, inline video + Picture-in-Picture, inline voice notes + continuous playback + `GlobalAudioPlayer`, composer voice-note recording (`⌘⇧A` + microphone picker), inline PDFs + file cards + drag-and-drop + downloads (`⌘O`, `⌘D`), inline locations + link previews + click-to-load embeds, the full-window `AttachmentCarousel` lightbox, and `MediaViewerBrowserWindow`.
   - Tasks 12–13 run final verification, update `docs/m4-acceptance.md`, and list the owner's by-hand check on live accounts.
2. **Milestone 4.5c — Emoji Autocomplete, Emoticons, Sticker Picker, and GIF Picker (short scope below, 10 inventory rows):**
   - Covers composer `:` emoji autocomplete (`Autocomplete.tsx`), emoticon-to-emoji replacement (`Disable automatic replacement of emoticons with emojis`), the composer emoji/media plus menu (`Emoji.tsx`, `EmojiItem.tsx`, `Enable emoji autocomplete`), the sticker picker (`StickerPicker.tsx`, `⌘⌥⇧S` `hotkey Message: Send Sticker` backed by local imported sticker packs), and the GIF picker (`GifPicker.tsx`, `⌘⇧G` `hotkey Message: Send GIF`, `/gif`, `Automatically send GIFs after selection`, using local GIF files by default and a privacy-gated opt-in search provider in 4.7).

---

## Summary for the Owner

### Today (what already exists in the engine and app)
- **Engine media store (`apps/desktop/courier/engine/internal/media/media.go`):** Content-addressed SHA-256 blob store at `<datadir>/media/<hash[:2]>/<hash>` (`Put`, `PutFile`, `Path`, `Has`), wired into `localmatrix/intent.go` (`UploadMedia`, `UploadMediaStream`, `DownloadMedia`, `DownloadMediaToFile`).
- **Engine file sending (`apps/desktop/courier/engine/internal/actions/actions.go`):** `SendFile` and `SendFileWith` enforce `MaxFileBytes = 90 * 1024 * 1024` (90 MB), sniff the first 512 bytes plus file extension (`detect` / `pickType`) to choose `m.image`, `m.video`, `m.audio`, or `m.file`, decode width/height for JPEG/PNG/GIF via `image.DecodeConfig`, copy the file into `media.Store`, and queue an outbox `event.MessageEventContent` with `mxc://courier.local/<sha256>`.
- **Engine search and Chat Info media (`apps/desktop/courier/engine/internal/actions/chatinfo.go`, `store/search.go`, `store/events.go`):** `events.go` already extracts `m.image`, `m.video`, `m.audio` (tagging `voice` when `org.matrix.msc3245.voice` is present), `m.file`, and `m.sticker` with `media_path`, `filename`, `mimetype`, `size`, `width`, `height`, and `caption`. `chatinfo.go` returns `shared_media`, `shared_files`, and `shared_links` (`http://`/`https://` URLs extracted from message bodies), and `search.query` supports `sections: ["media"]` and `kinds: ["text", "image", "video", "audio", "file", "sticker", "link"]`.
- **App thumbnails, quarantine cache, and basic chips (`ThumbnailLoader.swift`, `OpenFileCache.swift`, `AttachmentChip.swift`, `MessageBubble.swift`, `ComposerView.swift`, `Notifier.swift`):** `ThumbnailLoader` decodes `CGImage` thumbnails (`maxPixelSize = 640`, LRU 300 items / 160 MB). `OpenFileCache` clones hash-named blobs to `~/Library/Caches/com.vitruviansoftware.courier/open/<hash16>/<safeName>` and stamps `kLSQuarantineTypeOtherDownload` before opening in Finder/Quick Look. `MessageBubble` renders static `InlineImage` and `FileAttachmentChip` (which currently open external apps on click and show `[voice note]` as a plain file chip). `ComposerView` has `AttachmentPicker`, `PendingAttachmentChip`, and clipboard file paste. `Notifier` posts `UNMutableNotificationContent` text without `UNNotificationAttachment`.

### What 4.5b adds on top of Today
- **4.5a review follow-ups (Task 1):** `AppModel.mergedChats` becomes the single source of truth for merge definitions (removing duplicate stored copies on `InboxModel` and `ConversationModel`); a unit test and source scan fail if any new code compares `selectedRoomID ==` directly (fixing `PinnedStrip.swift:20` and `InboxModel.swift:644`) or sends a `"merge:…"` ID to an engine RPC outside `merge.*` and `room.events`; and `SearchModelTests.testSearchInMergedChatPassesMemberRoomIDs` waits deterministically without `Task.sleep`.
- **Per-network media capabilities and metadata (Tasks 2–4):** `room.features` exposes per-kind `FileFeatures` (`image`, `video`, `audio`, `voice`, `file`, `gif`, `sticker`, plus `location_supported`) read from each bridge's `GetCapabilities`. `Event` carries `blurhash`, `thumbnail_path`, `duration_ms`, `waveform`, `is_gif`, `is_animated`, `view_once`, `geo_uri`, `link_previews`, and `played`. Notifications attach local image/thumbnail files via `UNNotificationAttachment`.
- **Inline images, gallery grids, and view-once media (Task 5):** `EnhancedImg` decodes BlurHash placeholders while loading, shows `ImageError` if a blob is missing/corrupt, groups 2–10 consecutive image/video attachments from one message or burst into `GalleryGrouper` (`GalleryVideoPoster` for videos), and gates view-once media behind `ViewLimitedMediaViewer` (click-to-open modal, no save/copy, marks played on close).
- **Inline video and Picture-in-Picture (Task 6):** `BrandVideo` plays `mp4`/`mov`/`webm`/`3gp` inline with play/pause, scrub bar, duration, speed (`0.25×`–`2×`), mute, and fullscreen, plus a button that pops video into `PictureInPictureBrowserWindow` (`NSPanel` floating over all spaces while switching chats).
- **Inline voice notes, audio player, continuous playback, and recording (Tasks 7–8):** `Audio` renders the `MSC1767Audio` waveform scrubber, `0.5× / 1× / 1.5× / 2×` speed pill, played/unplayed dot, and context-menu **Mark as played**. When `Automatically play the next voice note` is on, finishing one voice note starts the next consecutive voice note in the chat and docks `GlobalAudioPlayer` at the top of the window when you switch chats. Pressing `⌘⇧A` (or `/voice` or the mic button) records from the selected `Microphone` input device with live waveform bars and `BrandStopButton`, sending via `message.sendVoice`.
- **Inline PDFs, file cards, drag-and-drop, and downloads (Task 9):** `PDFAttachment` and `PDF` (`PDFView`) step through PDF pages inline (**Previous Page** / **Next Page**, page count, **Open** / **Save As…**). Dragging files over the conversation shows `FileDropOverlay` (normal drop attaches to draft; holding `Shift` sends immediately). `⌘O` (`File ▸ Open…`) attaches files in the composer, and `⌘D` downloads attachments on the selected message respecting `Downloads location <path>` and `Always ask where to save files before downloading`.
- **Inline locations, link previews, and privacy-first embeds (Task 10):** `Location` renders a static local `MKMapSnapshotter` pin card with **Open in Apple Maps**, **Open in Google Maps**, and **Copy Location**. Incoming `com.beeper.linkpreviews` render title, domain, description, and local bridge-uploaded thumbnail without ever contacting the remote website. Outgoing messages attach a link preview only when the user opts in (`Disable link previews in outgoing messages` defaults to **on** on this Mac so Courier never contacts a link's server unless you turn previews on, and sets `BeeperLinkPreviews: []` when disabled so bridges suppress remote unfurling too). External embeds (`MessageIFrame`) default to a local click-to-load `🔒 Load Embed` card unless `Load external embeds automatically` is turned on.
- **Full-window attachment lightbox and Media Viewer window (Task 11):** Clicking any inline image or gallery tile opens `AttachmentCarousel` (zoom, pan, rotate 90°, flip horizontal/vertical, `←`/`→` prev/next, `Space` Quick Look, `D` download, `⌘C` copy image, react, reply, go to message). Running `Media viewer` from the command bar opens `MediaViewerBrowserWindow` with **Media**, **Links**, and **Docs** tabs, `MediaWithSender` tiles, **Sent By** (`All` / `You` / `Others`), **Sort by** (`Newest` / `Oldest`), debounced caption search, and multi-select **Download** / **Delete** / **Go to Message**.

### Surprises found in the pinned `bridgev2` and bridge sources
1. **Voice notes require different containers and MIME types per bridge when `ffmpeg` is absent.** In `mautrix-whatsapp` (`capabilities.go:130`, `from-matrix.go:609`), voice notes must be `audio/ogg; codecs=opus` (plain `audio/ogg` is marked `CapLevelUnsupported`, though `from-matrix.go:609` rewrites `audio/ogg` to `audio/ogg; codecs=opus`). In `mautrix-signal` (`capabilities.go:123`, `from-matrix.go:175`), native voice notes must be `audio/aac` (`audio/ogg` is only `CapLevelPartialSupport` and requires `ffmpeg.Supported()`). In `mautrix-gmessages` (`capabilities.go:167`, `handlematrix.go:251`), native voice notes are `audio/mp4` (`.m4a`). In `mautrix-slack` (`capabilities.go:142`, `from-matrix.go:155`), native `slack_audio` voice notes require `audio/webm; codecs=opus` or `audio/mp4` with an `.m4a` filename. In `mautrix-telegram` (`capabilities.go:154`), `audio/ogg`, `audio/mpeg`, and `audio/mp4` are all `CapLevelFullySupported`. Task 4 therefore records/packages M4A (`audio/mp4` / `audio/aac`) from macOS `AVAudioRecorder` and converts to OGG Opus (`audio/ogg; codecs=opus`) via `ffmpeg` when the room's `FileFeatures[CapMsgVoice]` requires `audio/ogg; codecs=opus` (WhatsApp), or falls back to a clear error if `ffmpeg` is missing on a WhatsApp voice note.
2. **None of the five bridges send or receive Matrix "voice note played" receipts.** Grepping `ReceiptType` and `played` across all five bridge modules shows that incoming and outgoing read receipts only map to standard read state; WhatsApp's `ReceiptTypePlayed` is not bridged in `mautrix-whatsapp@v0.2609.0`. Played state (`media_played`) is therefore stored locally in SQLite so Courier tracks which voice notes and view-once items you have opened on this Mac.
3. **Outgoing link preview suppression is controlled by sending an empty non-nil slice `com.beeper.linkpreviews: []`.** `mautrix-whatsapp` (`urlpreview.go:95`), `mautrix-telegram` (`handlematrix.go:481`, `NoWebpage: true`), and `mautrix-slack` (`from-matrix.go:117`, `MsgOptionDisableLinkUnfurl()`) all check `content.BeeperLinkPreviews != nil && len(content.BeeperLinkPreviews) == 0` to suppress server-side/bridge-side link unfurling. When `Disable link previews in outgoing messages` is on, Courier sends `"com.beeper.linkpreviews": []` on `m.text` events so neither the Mac nor the bridge/server generates a preview.
4. **View-once media is converted into short after-read disappearing timers by Signal and Telegram, bridged as normal media by WhatsApp, and absent in Google Messages and Slack.** None of the five bridges set `FileFeatures.ViewOnce: true` for outgoing messages (`maunium.net/go/mautrix@v0.31.0/event/capabilities.go:276`). Incoming view-once on Signal sets a 5-minute after-read timer (`from-signal.go:81, 162`), and on Telegram (`ttl == 2147483647`) sets a 15-second after-read timer (`tomatrix.go:568`). Task 3 detects view-once on incoming events from either an explicit `"com.beeper.view_once": true` / `view_once` content flag or an `after_read` timer `<= 300s` on a media event so `ViewLimitedMediaViewer` gates viewing and suppresses local save/copy.
5. **GIFs are `m.video` (`video/mp4` + `fi.mau.gif: true`) on WhatsApp and Telegram, `m.image` or `m.video` on Signal, and `m.image` (`image/gif`) on Google Messages and Slack.** `Timeline.swift` and `MessageBubble.swift` must treat both `m.image` with `mimetype == "image/gif"` and `m.video` with `info.fi.mau.gif == true` as looping muted auto-playing GIFs (`is_gif = true`).
6. **Location messages (`m.location`) are fully supported on WhatsApp and Telegram, converted to a text link on Signal (`from-matrix.go:131`), rejected on Slack (`capabilities.go:185`), and unsupported on Google Messages (`capabilities.go:67`).** Incoming `m.location` renders `Location` in all chats; outgoing `message.sendLocation` checks `room.features` (`location_supported`).

### Decisions for the owner to check
1. **4.5b / 4.5c split:** 4.5b ships all media playback, voice recording, inline viewers (images, galleries, video, PiP, audio, PDFs, files, locations, link previews, embeds), downloads, lightbox, and the Media Viewer window (Tasks 1–13). 4.5c will ship emoji/emoticon composer tools and the sticker and GIF pickers.
2. **Privacy-first link previews and external embeds (Hard Rule 4):**
   - Incoming link previews (`com.beeper.linkpreviews`) only render the text metadata and `mxc://courier.local/...` thumbnail already delivered by the bridge into `media.Store`. If a preview references an external `http(s)://` image URL, Courier ignores the image URL and never fetches it.
   - Outgoing link previews: `Disable link previews in outgoing messages` defaults to **`true`** so Courier never contacts a URL's server when you type or send a link unless you turn that setting off. When `Disable link previews in outgoing messages` is `true`, `message.send` also sets `BeeperLinkPreviews: []` on the Matrix event so WhatsApp, Telegram, and Slack suppress bridge/server unfurling. When the user turns `Disable link previews in outgoing messages` **off**, the engine fetches only the first `https://` URL in the outgoing message on send (timeout 3 s, max 256 KB HTML + 2 MB `og:image`, stored in `media.Store`) to populate `BeeperLinkPreviews`.
   - External embeds (`MessageIFrame`): `Load external embeds automatically` defaults to **`false`**, rendering a local placeholder card (`🔒 Load Embed from <host>`) with no `WKWebView` instantiated and zero network traffic until clicked.
3. **Engine `MaxFileBytes` ceiling vs per-bridge `FileFeatures.MaxSize`:** `actions.go`'s hard safety cap moves from `90 MB` to the minimum of the bridge's `FileFeatures.MaxSize` for that media kind (e.g., `100 MiB` on Signal and Google Messages, `1 GB` on Slack, `2 GiB` on WhatsApp and Telegram) and a local `2 GiB` cap when `FileFeatures` is unavailable.

### Main risks the tests target
- **Regressing merged-chat selection or leaking `"merge:…"` IDs to engine RPCs:** tested by `TestNoDirectSelectedRoomIDComparisonsInSources` and `TestEngineRejectsMergeIDsOnRoomScopedRPCs` in Task 1.
- **Voice-note MIME mismatch across bridges:** tested per bridge capability in `TestSendVoiceSelectsContainerPerBridgeCapabilities` (`actions_test.go`) and against all 5 real bridge connectors in `TestMediaCapabilitiesTableMatchesTheBridges` (`networks_test.go`).
- **Unconsented network requests on link previews or external embeds:** tested in `TestSendMessageSuppressesLinkPreviewByDefaultAndFetchesOnlyWhenEnabled` (`actions_test.go`) and `testExternalEmbedNeverLoadsUntilClickedWhenAutoLoadOff` (`ConversationModelTests.swift`).
- **Continuous voice-note playback across messages and chats:** tested in `AudioPlayerModelTests.swift` (advancing through consecutive voice notes, marking each played, and docking `GlobalAudioPlayer` when switching rooms).

---

## Per-Network Capability Table (Verified in Pinned Bridge Sources)

Pinned in `apps/desktop/courier/engine/go.mod`: `maunium.net/go/mautrix` **v0.31.0**, `go.mau.fi/mautrix-whatsapp` **v0.2609.0**, `mautrix-signal` **v0.2609.0**, `mautrix-telegram` **v0.2609.0**, `mautrix-gmessages` **v0.2609.0**, `mautrix-slack` **v0.2609.1**. Every cell below was verified in `~/go/pkg/mod` at those exact versions (grep commands in the Appendix).

| Capability / Media Feature | WhatsApp (`mautrix-whatsapp@v0.2609.0`) | Signal (`mautrix-signal@v0.2609.0`) | Telegram (`mautrix-telegram@v0.2609.0`) | Google Messages (`mautrix-gmessages@v0.2609.0`) | Slack (`mautrix-slack@v0.2609.1`) |
|---|---|---|---|---|---|
| Max file size (`FileFeatures.MaxSize`) | `2000 * 1024 * 1024` (2000 MiB) `pkg/connector/capabilities.go:58,99` | `100 * 1024 * 1024` (100 MiB) `pkg/connector/capabilities.go:48,70` | `2 * 1024 * 1024 * 1024` (2 GiB; 4 GiB Premium; `10 MiB` `MsgImage` photo) `pkg/connector/capabilities.go:73,109,173` | `100 * 1024 * 1024` (100 MiB RCS; `1 MiB` MMS) `pkg/connector/capabilities.go:34,69,89` | `1 * 1000 * 1000 * 1000` (1 GB) `pkg/connector/capabilities.go:91,111` |
| Images (`m.image`) & captions | `image/jpeg` full, `png`/`webp` partial, `gif` partial if ffmpeg; caption up to `65536` `pkg/connector/capabilities.go:63,95-106` | `gif`/`png`/`jpeg`/`webp`/`bmp`/`avif` full (`4096×4096`); caption up to `2000` `pkg/connector/capabilities.go:50,59-74` | `image/jpeg` full, `webp`/`png`/`gif` partial (`10 MiB` photo, larger sent as doc `pkg/connector/handlematrix.go:290`); caption `1024` (`2048` Premium) `pkg/connector/capabilities.go:75,103-112,176` | `png`/`jpeg`/`gif`/`bmp`/`wbmp`/`webp` full; RCS sends caption as separate text message `pkg/connector/capabilities.go:81-91`, `pkg/connector/handlematrix.go:226-232` | `jpeg`/`png`/`gif`/`webp` full; caption up to `40000` `pkg/connector/capabilities.go:93,103-113` |
| Videos (`m.video`) | `video/mp4`, `video/3gpp` full; `webm`/`quicktime` partial if ffmpeg; caption full `pkg/connector/capabilities.go:107-116` | `video/mp4`, `video/ogg`, `video/webm` full; caption full `pkg/connector/capabilities.go:76-85` | `video/mp4` full (`2 GiB` / `4 GiB` Premium); caption full `pkg/connector/capabilities.go:113-119` | `video/mp4`, `video/3gpp`, `video/webm` full (`100 MiB` RCS) `pkg/connector/capabilities.go:121-130` | `video/mp4`, `video/webm` full (`1 GB`); caption full `pkg/connector/capabilities.go:115-122` |
| Audio files (`m.audio`) | `mpeg`/`mp4`/`ogg`/`aac`/`amr` full; caption dropped `pkg/connector/capabilities.go:117-128` | `aac`/`mpeg`/`mp3`/`flac` full; caption unsupported `pkg/connector/capabilities.go:86-96` | `audio/mpeg`, `audio/mp4` full; caption full `pkg/connector/capabilities.go:120-127` | `aac`/`amr`/`mpeg`/`mp4`/`mp4-latm`/`3gpp`/`ogg` full `pkg/connector/capabilities.go:100-119` | `audio/mpeg`, `audio/webm`, `audio/wav` full; caption full `pkg/connector/capabilities.go:124-131` |
| Voice notes (`org.matrix.msc3245.voice`) & waveform (`org.matrix.msc1767.audio`) | `audio/ogg; codecs=opus` full (`audio/ogg` rewritten at `pkg/msgconv/from-matrix.go:609`); waveform 0..100 & duration both ways `pkg/connector/capabilities.go:129-135`, `pkg/msgconv/wa-media.go:294-304`, `pkg/msgconv/from-matrix.go:664-680` | Outgoing `audio/aac` full (`audio/ogg` converted via ffmpeg `pkg/msgconv/from-matrix.go:168-198`), max `3600s`; incoming converted to `.ogg` opus if ffmpeg, waveform commented out `pkg/connector/capabilities.go:121-133`, `pkg/msgconv/from-signal.go:616-657` | `audio/ogg`, `audio/mpeg`, `audio/mp4` full; 5-bit packed waveform & duration both ways `pkg/connector/capabilities.go:154-162`, `pkg/connector/tomatrix.go:678-696`, `pkg/connector/handlematrix.go:355-363` | Outgoing `audio/mp4` full (`audio/ogg` converted via ffmpeg to `.m4a` `pkg/connector/handlematrix.go:251-258`); incoming tagged `MSC3245Voice` and converted to `.ogg` if ffmpeg `pkg/connector/capabilities.go:165-177`, `pkg/connector/handlegmessages.go:1496-1542` | `audio/webm; codecs=opus` & `audio/mp4` (`.m4a`) full (`audio/ogg` partial via ffmpeg), max `300s`; incoming `slack_audio` has waveform & duration `pkg/connector/capabilities.go:140-156`, `pkg/msgconv/from-matrix.go:149-165`, `pkg/msgconv/from-slack.go:327-365` |
| Voice-note played receipts | unverified (not bridged in `mautrix-whatsapp@v0.2609.0`; `pkg/connector/events.go` only handles read/delivery receipts) | unverified (not bridged in `mautrix-signal@v0.2609.0`) | unverified (not bridged in `mautrix-telegram@v0.2609.0`) | unverified (not bridged in `mautrix-gmessages@v0.2609.0`) | unverified (not bridged in `mautrix-slack@v0.2609.1`) |
| Generic files & PDFs (`m.file`) | `*/*` full (`2000 MiB`), caption full `pkg/connector/capabilities.go:159-165` | `*/*` full (`100 MiB`), caption full `pkg/connector/capabilities.go:97-104` | `*/*` full (`2 GiB` / `4 GiB` Premium), caption full `pkg/connector/capabilities.go:128-134` | `application/*`, `text/*` full (`100 MiB` RCS) `pkg/connector/capabilities.go:142-151` | `*/*` full (`1 GB`), caption full `pkg/connector/capabilities.go:132-138` |
| GIFs (`fi.mau.gif` / `image/gif`) | `video/mp4` (`GifPlayback`) full, `image/gif` transcoded via ffmpeg `pkg/connector/capabilities.go:149-158`, `pkg/msgconv/wa-media.go:310-318`, `pkg/msgconv/from-matrix.go:248-257` | `image/gif` & `video/mp4` full `pkg/connector/capabilities.go:134-142` | `video/mp4` full, `image/gif` partial `pkg/connector/capabilities.go:135-142` | `image/gif` full `pkg/connector/capabilities.go:180-189` | `image/gif` full `pkg/connector/capabilities.go:157-164` |
| Stickers (`m.sticker`) | `image/webp` full, `png`/`jpeg`/`video/lottie+json` partial; no caption `pkg/connector/capabilities.go:136-148` | `image/png`, `image/apng` full, `webp` partial, `gif` partial if ffmpeg; no caption `pkg/connector/capabilities.go:105-120` | `image/webp`, `video/lottie+json`, `video/webm` full, `jpeg`/`png` partial `pkg/connector/capabilities.go:143-153` | — (`CapMsgSticker` absent in `pkg/connector/capabilities.go:80-190`) | — (`CapMsgSticker` absent in `capabilities.go`; outgoing `m.sticker` converted to `m.image` at `pkg/msgconv/from-matrix.go:68-71`) |
| View-once media (`ViewOnce`) | Outgoing `FileFeatures.ViewOnce` false (`capabilities.go:95-165`); incoming view-once bridged as normal media when `DisableViewOnce` is false `pkg/msgconv/wa-media.go:49-64` | Outgoing `FileFeatures.ViewOnce` false; incoming `dm.GetIsViewOnce()` sets `5m` after-read disappearing timer when `DisappearViewOnce` is true `pkg/msgconv/from-signal.go:81,162-164` | Outgoing `FileFeatures.ViewOnce` false; incoming `ttl == 2147483647` sets `15s` after-read disappearing timer `pkg/connector/tomatrix.go:568-571` | — (not in `mautrix-gmessages@v0.2609.0`) | — (not in `mautrix-slack@v0.2609.1`) |
| Location messages (`m.location`) | `CapLevelFullySupported` both ways (`GeoURI` `geo:<lat>,<long>`) `pkg/connector/capabilities.go:178`, `pkg/msgconv/wa-location.go:33-57`, `pkg/msgconv/from-matrix.go:125-135` | `CapLevelPartialSupport` (incoming location; outgoing `GeoURI` formatted as text URL) `pkg/connector/capabilities.go:158`, `pkg/msgconv/from-matrix.go:131-139` | `CapLevelFullySupported` both ways (`GeoURI` / `InputMediaGeoPoint`) `pkg/connector/capabilities.go:222`, `pkg/connector/tomatrix.go:899-956`, `pkg/connector/handlematrix.go:552-573` | — (`LocationMessage` unset in `pkg/connector/capabilities.go:67-79`) | `CapLevelRejected` `pkg/connector/capabilities.go:185` |
| Link previews (`com.beeper.linkpreviews`) | `CapLevelFullySupported` incoming & outgoing; `BeeperLinkPreviews: []` suppresses preview `pkg/connector/capabilities.go:185`, `pkg/msgconv/urlpreview.go:38-135` | `CapLevelFullySupported` incoming & outgoing (`BeeperLinkPreviews` with uploaded image) `pkg/connector/capabilities.go:164`, `pkg/msgconv/urlpreview.go:30-93` | Incoming webpage media -> `BeeperLinkPreview`; outgoing `BeeperLinkPreviews: []` sets `NoWebpage: true` `pkg/connector/tomatrix.go:201-207,471-506`, `pkg/connector/handlematrix.go:481` | — (not in `mautrix-gmessages@v0.2609.0`) | Incoming attachments -> `BeeperLinkPreview`; outgoing `BeeperLinkPreviews: []` sets `MsgOptionDisableLinkUnfurl()` `pkg/msgconv/blocks.go:93-136,650,675`, `pkg/msgconv/from-matrix.go:117-119` |
| BlurHash on attachments (`xyz.amorgan.blurhash` / `blurhash`) | Field in shared `event.FileInfo` (`mautrix@v0.31.0/event/message.go:341-342`); not computed by `mautrix-whatsapp` | Preserved incoming & outgoing (`Blurhash` / `AnoaBlurhash`) `pkg/msgconv/from-signal.go:569-572`, `pkg/msgconv/from-matrix.go:206-210` | Field in shared `event.FileInfo`; not computed by `mautrix-telegram` | Field in shared `event.FileInfo`; not computed by `mautrix-gmessages` | Field in shared `event.FileInfo`; not computed by `mautrix-slack` |

---

## Global Constraints

1. **Bazel-only repo and toolchain operations:** Run every build, test, tidy, gazelle, format, lint, and git operation through its Bazel target per `AGENTS.md`: `bazel test //apps/desktop/courier/...`, `bazel run //:tidy`, `bazel run //:gazelle`, `bazel run //tools/format`, `aspect lint //apps/desktop/courier/...`, `bazel run //tools/git:commit -- --agent <you> ...`, and `bazel run //tools/git:push -- --agent <you>`. Never run raw `git commit`, `git push`, `go test`, or `swift test`.
2. **Protocol & schema versions:** Protocol bumps from `6` to `7` in `apps/desktop/courier/protocol/protocol.json`, `apps/desktop/courier/engine/internal/rpc/server.go`, and `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`. All protocol changes are additive and use `snake_case` JSON keys. Store schema bumps from `8` to `9` as a new entry in `apps/desktop/courier/engine/internal/store/migrate.go` (`schema.sql` is the version-0 baseline and is **never** edited). Migration 8's SHA-256 is pinned in `TestShippedMigrationsAreUnchanged` (`migrate_test.go`), and a 4.5a snapshot `testdata/m9.sql` is tested via `TestMigrationFromMilestone4_5a` (`store_test.go`).
3. **Privacy (Hard Rule 4):** Media stays on this Mac except when sent to the chat it belongs to. No thumbnails, link previews, or external embeds may be fetched from a third party without the person asking. Incoming link previews only display metadata and `mxc://courier.local/...` images already stored in `media.Store`. Outgoing link previews are suppressed by default (`Disable link previews in outgoing messages` = `true`, sending `com.beeper.linkpreviews: []`); only when the user turns that setting off does the engine fetch `og:*` metadata on send. External embeds (`MessageIFrame`) default to click-to-load (`Load external embeds automatically` = `false`).
4. **No sleeps or wall-clock flake in tests:** Inject clocks (`store.WithNow`, `actions.WithNow`, Swift `now: () -> Date`) and synchronize on channels or deterministic condition helpers (`waitUntil`).
5. **View verification (Hard Rule 5):** Every new or modified SwiftUI surface in `apps/desktop/courier/app/Sources/Courier/` is checked by light and dark PNG snapshot tests in `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift` (`bazel test //apps/desktop/courier/app:CourierViewTests`). There is no fake-network app mode; live network verification happens in Task 13 (owner's by-hand day).

## Review Focus

- **4.5a follow-ups enforced mechanically:** verify in Task 1 that `AppModel.mergedChats` is the sole stored owner of merge definitions, that `TestNoDirectSelectedRoomIDComparisonsInSources` fails if any file in `Sources/` writes `selectedRoomID ==` or `== selectedRoomID` outside `AppModel.isOpen`, that `TestEngineServer` rejects `"merge:…"` on room-scoped RPCs, and that `SearchModelTests.swift:659` has no `Task.sleep`.
- **Per-kind `FileFeatures` derived from `bridgev2` capabilities:** verify in Task 2 that `engine/internal/actions/features.go` reads `RoomFeatures.File` (`MsgImage`, `MsgVideo`, `MsgAudio`, `CapMsgVoice`, `MsgFile`, `CapMsgGIF`, `CapMsgSticker`) and `LocationMessage` without switching on `room.Network`.
- **Privacy defaults on link previews and external embeds:** verify in Tasks 4 and 10 that zero third-party HTTP requests happen when rendering incoming messages or sending outgoing messages under default settings.
- **Quarantine attribute on all downloaded/opened files:** verify in Task 9 that saving a file via `⌘D` or opening via Quick Look / Finder preserves `kLSQuarantineTypeOtherDownload` (`OpenFileCache.swift`).

---

## Tasks

### Task 1: 4.5a Review Follow-Ups — Single Owner for Merge Definitions, `selectedRoomID ==` & `"merge:…"` Guards, and No-Sleep Merged-Chat `⌘F` Test

**Files:**
- Modify: `apps/desktop/courier/app/Sources/CourierCore/AppModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/InboxModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ConversationModel.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/PinnedStrip.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/TestEngineServer.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/SearchModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/InboxSelectionTests.swift`

**Interfaces:**
- In `AppModel.swift`:
  ```swift
  @Published public var mergedChats: [String: MergedChat] = [:]

  /// The member room IDs for a selection or scope ID: if `id` is a `"merge:…"` ID in `mergedChats`,
  /// returns its `rooms.map(\.roomID)`; otherwise returns `[id]`.
  public func scopeRoomIDs(for id: String) -> [String] {
      if let merged = mergedChats[id], !merged.rooms.isEmpty {
          return merged.rooms.map(\.roomID)
      }
      return [id]
  }
  ```
- In `InboxModel.swift`: remove `@Published public private(set) var mergedChats: [String: MergedChat]` and read/write `appModel.mergedChats` directly via a computed property `public var mergedChats: [String: MergedChat] { appModel.mergedChats }`; replace `selectedRoomID == nil` at line 644 with `appModel.openRoomIDs.isEmpty`.
- In `ConversationModel.swift`: remove `@Published public private(set) var mergedChat: MergedChat?` stored copy and compute `public var mergedChat: MergedChat? { roomID.flatMap { appModel.mergedChats[$0] } }`, writing updates to `appModel.mergedChats[merged.mergeID] = merged`.
- In `PinnedStrip.swift`: replace `inbox.selectedRoomID == row.id` at line 20 with `inbox.isOpen(row.id)`.
- In `TestEngineServer.swift`: inspect incoming RPC requests before calling the handler; if any `"room_id"` or `"room_ids"` element starts with `"merge:"` on any method, fail the test immediately with `XCTFail("Engine RPC \(method) received synthetic merge ID: \(id)")`.

**Steps:**
- [ ] **Step 1: Write failing tests in `InboxSelectionTests.swift` and update `TestEngineServer.swift` and `SearchModelTests.swift`.**
  - In `InboxSelectionTests.swift`, add:
    - `testSingleMergedChatsOwnerAcrossAppInboxAndConversation`: mutates `appModel.mergedChats["merge:1"]` and asserts `inbox.mergedChats["merge:1"]` and `conversation.mergedChat` (when open on `"merge:1"`) immediately reflect the update without secondary dictionary copies.
    - `testNoDirectSelectedRoomIDComparisonsInSources`: walks all `.swift` files under `apps/desktop/courier/app/Sources/` (resolved relative to `#filePath`) and asserts that no line contains `selectedRoomID ==` or `== selectedRoomID` except inside `AppModel.swift`'s `isOpen(roomID:)`.
    - `testEngineServerGuardRejectsMergeIDInRoomScopedRPC`: sends a `room.markRead` with `room_id: "merge:alice"` against `TestEngineServer` in negative-assertion mode and verifies the guard catches it.
  - In `SearchModelTests.swift:659` (`testSearchInMergedChatPassesMemberRoomIDs`), replace `try await Task.sleep(for: .milliseconds(50))` with `try await waitUntil { h.search.scope?.id == "merge:alice" }`.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests` and confirm `testNoDirectSelectedRoomIDComparisonsInSources` fails on `PinnedStrip.swift:20` and `InboxModel.swift:644`.**
- [ ] **Step 3: Consolidate `mergedChats` onto `AppModel`, add `scopeRoomIDs(for:)`, and replace the two remaining `selectedRoomID ==` comparisons in `PinnedStrip.swift` and `InboxModel.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 1.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "refactor(courier): unify mergedChats owner and guard against raw selectedRoomID and merge IDs" apps/desktop/courier/app`

---

### Task 2: Store Migration 9 & Protocol v7 — Rich Media Metadata, Per-Kind File Capabilities, Played State, Voice Notes, and Locations

**Files:**
- Modify: `apps/desktop/courier/engine/internal/store/migrate.go`
- Modify: `apps/desktop/courier/engine/internal/store/migrate_test.go`
- Create: `apps/desktop/courier/engine/internal/store/testdata/m9.sql`
- Modify: `apps/desktop/courier/engine/internal/store/store.go`
- Modify: `apps/desktop/courier/engine/internal/store/store_test.go`
- Modify: `apps/desktop/courier/engine/internal/store/events.go`
- Modify: `apps/desktop/courier/engine/internal/store/events_test.go`
- Modify: `apps/desktop/courier/engine/internal/actions/features.go`
- Modify: `apps/desktop/courier/engine/internal/actions/features_test.go`
- Modify: `apps/desktop/courier/engine/internal/networks/networks_test.go`
- Modify: `apps/desktop/courier/protocol/protocol.json`
- Modify: `apps/desktop/courier/protocol/examples/hello.json`
- Modify: `apps/desktop/courier/protocol/examples/hello-protocol-mismatch.json`
- Modify: `apps/desktop/courier/protocol/examples/room.features.json`
- Create: `apps/desktop/courier/protocol/examples/message.markPlayed.json`
- Create: `apps/desktop/courier/protocol/examples/message.sendVoice.json`
- Create: `apps/desktop/courier/protocol/examples/message.sendLocation.json`
- Modify: `apps/desktop/courier/engine/internal/rpc/server.go`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Protocol.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ChatFeatures.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ChatFeaturesTests.swift`

**Interfaces:**
- Migration 9 (`version: 9` in `migrate.go`, bumping `SchemaVersion = 9`):
  ```sql
  CREATE TABLE IF NOT EXISTS media_played (
      room_id    TEXT NOT NULL,
      event_id   TEXT NOT NULL,
      played_ts  INTEGER NOT NULL,
      PRIMARY KEY (room_id, event_id)
  ) STRICT;
  ```
- In `store.go`:
  ```go
  func (s *Store) MarkMediaPlayed(ctx context.Context, roomID, eventID string, playedTS int64) error
  func (s *Store) IsMediaPlayed(ctx context.Context, roomID, eventID string) (bool, error)
  func (s *Store) MediaPlayedSet(ctx context.Context, roomID string, eventIDs []string) (map[string]bool, error)
  ```
- In `protocol.json` (bumping `"version": 7`):
  - Add `FileKindFeatures` and extend `ChatFeatures` (`room.features`):
    ```json
    "FileKindFeatures": {
      "supported": "bool",
      "mime_types": "[string]?",
      "caption": "bool",
      "max_caption_length": "int?",
      "max_size": "int?",
      "max_duration_sec": "int?"
    }
    ```
    Add optional fields on `ChatFeatures`: `"image_features": "FileKindFeatures?"`, `"video_features": "FileKindFeatures?"`, `"audio_features": "FileKindFeatures?"`, `"voice_features": "FileKindFeatures?"`, `"file_features": "FileKindFeatures?"`, `"gif_features": "FileKindFeatures?"`, `"sticker_features": "FileKindFeatures?"`, `"location_supported": "bool?"`, `"link_previews_supported": "bool?"`.
  - Add `LinkPreviewItem` and extend `Event`:
    ```json
    "LinkPreviewItem": {
      "matched_url": "string",
      "url": "string?",
      "title": "string?",
      "site_name": "string?",
      "description": "string?",
      "image_path": "string?",
      "image_width": "int?",
      "image_height": "int?",
      "blurhash": "string?"
    }
    ```
    Add optional fields on `Event`: `"thumbnail_path": "string?"`, `"blurhash": "string?"`, `"duration_ms": "int?"`, `"waveform": "[int]?"`, `"is_gif": "bool?"`, `"is_animated": "bool?"`, `"view_once": "bool?"`, `"geo_uri": "string?"`, `"link_previews": "[LinkPreviewItem]?"`, `"played": "bool?"`.
    Add `"location"` to `Event.kind` description (`"text" | "emote" | "image" | "video" | "voice" | "file" | "sticker" | "location" | "poll" | "member" | "call_note" | "timer_note" | "unknown"`).
  - Extend `SendParams` (`message.send`) with `"disable_link_preview": "bool?"`.
  - Add RPC methods:
    - `message.markPlayed`: params `MarkPlayedParams { "room_id": "string", "event_id": "string" }`, result `Empty`.
    - `message.sendVoice`: params `SendVoiceParams { "room_id": "string", "path": "string", "duration_ms": "int", "waveform": "[int]?", "reply_to": "string?" }`, result `SendResult`.
    - `message.sendLocation`: params `SendLocationParams { "room_id": "string", "latitude": "float", "longitude": "float", "label": "string?", "reply_to": "string?" }`, result `SendResult`.
- In `engine/internal/actions/features.go`:
  - Map `rc.File[event.MsgImage]`, `rc.File[event.MsgVideo]`, `rc.File[event.MsgAudio]`, `rc.File[event.CapMsgVoice]`, `rc.File[event.MsgFile]`, `rc.File[event.CapMsgGIF]`, `rc.File[event.CapMsgSticker]` (via `convertFileFeatures(ff *event.FileFeatures)`) and `rc.LocationMessage >= event.CapLevelPartialSupport` + `rc.SendURLPreviews >= event.CapLevelPartialSupport` onto `actions.RoomFeatures`.

**Steps:**
- [ ] **Step 1: Pin migration 8's hash and write failing tests in `migrate_test.go`, `store_test.go`, `features_test.go`, `networks_test.go`, and `ChatFeaturesTests.swift`.**
  - In `migrate_test.go`, add migration 8's SHA-256 to `TestShippedMigrationsAreUnchanged`.
  - Create `testdata/m9.sql` capturing a v8 database (`PRAGMA user_version = 8`) with `merged_chats` and `merged_chat_rooms` from 4.5a.
  - In `store_test.go`, add `TestMigrationFromMilestone4_5a` and `TestMarkAndQueryMediaPlayed`.
  - In `features_test.go`, add `TestFileKindFeaturesMappedFromRoomCapabilities` verifying `MaxSize`, `MaxDuration`, `Caption`, `MimeTypes`, `LocationSupported`, and `LinkPreviewsSupported`.
  - In `networks_test.go`, add `TestMediaCapabilitiesTableMatchesTheBridges` asserting the per-network table's `MaxSize`, `CapMsgVoice` MIME types, `CapMsgSticker` presence, `LocationMessage`, and `SendURLPreviews` against all 5 real bridge connectors.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/store:store_test //apps/desktop/courier/engine/internal/actions:actions_test //apps/desktop/courier/engine/internal/networks:networks_test` and confirm failure.**
- [ ] **Step 3: Implement migration 9, `MarkMediaPlayed`/`MediaPlayedSet`, `features.go` file capability mapping, `protocol.json` v7 + example fixtures, and `Protocol.swift` / `ChatFeatures.swift`.**
- [ ] **Step 4: Re-run engine and Swift protocol conformance tests (`bazel test //apps/desktop/courier/engine/... //apps/desktop/courier/app:CourierCoreTests`) and confirm `PASS`.**
- [ ] **Step 5: Commit Task 2.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): bump to protocol v7 and schema v9 for rich media metadata and file capabilities" apps/desktop/courier/protocol apps/desktop/courier/engine apps/desktop/courier/app`

---

### Task 3: Engine Media Inspection — Dimensions, BlurHash, Poster Frames, Audio Waveforms, Link Previews, and View-Once Detection

**Files:**
- Create: `apps/desktop/courier/engine/internal/media/blurhash.go`
- Create: `apps/desktop/courier/engine/internal/media/blurhash_test.go`
- Create: `apps/desktop/courier/engine/internal/media/inspect.go`
- Create: `apps/desktop/courier/engine/internal/media/inspect_test.go`
- Modify: `apps/desktop/courier/engine/internal/media/BUILD`
- Modify: `apps/desktop/courier/engine/internal/store/events.go`
- Modify: `apps/desktop/courier/engine/internal/store/events_test.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/messages.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/messages_test.go`

**Interfaces:**
- In `engine/internal/media/blurhash.go`:
  ```go
  // EncodeBlurHash computes a compact 4x3 BlurHash string from an image.Image
  // after downsampling to at most 32x32 pixels in pure Go.
  func EncodeBlurHash(img image.Image) string
  ```
- In `engine/internal/media/inspect.go`:
  ```go
  type Metadata struct {
      Width      int
      Height     int
      BlurHash   string
      IsAnimated bool
  }

  // InspectImage decodes dimensions and computes a 4x3 BlurHash for JPEG, PNG, GIF (detecting multi-frame GIFs), and WebP.
  func InspectImage(r io.Reader) (Metadata, error)
  ```
- In `engine/internal/store/events.go`:
  - Extend `Event` struct with `ThumbnailPath string`, `BlurHash string`, `DurationMS int`, `Waveform []int`, `IsGIF bool`, `IsAnimated bool`, `ViewOnce bool`, `GeoURI string`, `LinkPreviews []LinkPreview`, `Played bool`.
  - In `extractEvent`:
    - Parse `info.thumbnail_url` (`mxc://courier.local/<hash>`) -> `ThumbnailPath`.
    - Parse `info.xyz.amorgan.blurhash` or `info.blurhash` -> `BlurHash`.
    - Parse `org.matrix.msc1767.audio` (`duration`, `waveform`) and fallback `info.duration` -> `DurationMS`, `Waveform`.
    - Parse `info.fi.mau.gif` or `mimetype == "image/gif"` -> `IsGIF`; `info.is_animated` -> `IsAnimated`.
    - Parse `m.location` (`geo_uri`) -> `Kind: "location"`, `GeoURI`.
    - Parse `com.beeper.linkpreviews` -> `LinkPreviews`, resolving `og:image` **only** if it is an `mxc://courier.local/<hash>` URI in `media.Store` (ignoring any external `http://` or `https://` image URL so the Mac never fetches third-party preview images).
    - Detect `ViewOnce`: `true` when content has `"com.beeper.view_once": true` or `"view_once": true`, or when the event is a media kind (`image`, `video`, `voice`) with an `after_read` disappearing timer `<= 300000` ms (covering Signal's 5-minute and Telegram's 15-second view-once timers).
    - When `ViewOnce && Played` is true, clear `MediaPath` and `ThumbnailPath` in the RPC response so view-once media cannot be re-opened after viewing.

**Steps:**
- [ ] **Step 1: Write failing unit tests in `blurhash_test.go`, `inspect_test.go`, `events_test.go`, and `messages_test.go`.**
  - `TestEncodeBlurHashAndInspectImage`: verifies JPEG, PNG, multi-frame animated GIF (`IsAnimated: true`), and WebP dimensions + non-empty 4x3 BlurHash.
  - `TestExtractEventPopulatesWaveformBlurHashLocationLinkPreviewsAndViewOnce`: verifies `msc1767.audio` waveform/duration, `xyz.amorgan.blurhash`, `m.location` `geo:37.7749,-122.4194`, `com.beeper.linkpreviews` with `mxc://courier.local/...` image vs dropped `https://evil.example/track.png` image, and view-once detection + path redaction once `MarkMediaPlayed` is called.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/media/... //apps/desktop/courier/engine/internal/store/... //apps/desktop/courier/engine/internal/rpc/...` and confirm failure.**
- [ ] **Step 3: Implement `blurhash.go`, `inspect.go`, `events.go` extraction, and `rpc/messages.go` mapping (including `message.markPlayed`). Run `bazel run //:gazelle` to update `media/BUILD`.**
- [ ] **Step 4: Re-run the engine tests and confirm `PASS`.**
- [ ] **Step 5: Commit Task 3.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): extract BlurHash, waveforms, locations, local link previews, and view-once state" apps/desktop/courier/engine`

---

### Task 4: Engine Media Actions — Voice-Note Transcoding (`message.sendVoice`), Location Sending (`message.sendLocation`), Outgoing Link-Preview Suppression, and Notification Attachments

**Files:**
- Create: `apps/desktop/courier/engine/internal/actions/voice.go`
- Create: `apps/desktop/courier/engine/internal/actions/linkpreview.go`
- Modify: `apps/desktop/courier/engine/internal/actions/actions.go`
- Modify: `apps/desktop/courier/engine/internal/actions/outbox.go`
- Modify: `apps/desktop/courier/engine/internal/actions/send_test.go`
- Modify: `apps/desktop/courier/engine/internal/actions/BUILD`
- Modify: `apps/desktop/courier/engine/internal/rpc/messages.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/methods.go`
- Modify: `apps/desktop/courier/engine/internal/rpc/conformance_test.go`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/NotificationCoordinator.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/Notifier.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/NotificationCoordinatorTests.swift`

**Interfaces:**
- In `engine/internal/actions/voice.go`:
  ```go
  type SendVoiceOpts struct {
      DurationMS int
      Waveform   []int
      ReplyTo    string
      FFmpegPath string // optional override for tests; defaults to exec.LookPath("ffmpeg")
  }

  // SendVoice stores and queues a voice note (m.audio + org.matrix.msc3245.voice + org.matrix.msc1767.audio).
  // Inspects the room's CapMsgVoice FileFeatures:
  // - If the bridge supports audio/mp4 or audio/aac (Signal, Telegram, Google Messages, Slack), keeps M4A/AAC (or OGG if already OGG on Telegram).
  // - If the bridge requires audio/ogg; codecs=opus (WhatsApp) and the input is M4A/AAC/WAV, transcodes via ffmpeg (-c:a libopus -application voip). If ffmpeg is not found, returns ErrVoiceTranscodeUnavailable.
  func (a *Actions) SendVoice(ctx context.Context, roomID, path string, opts SendVoiceOpts) (SendResult, error)

  // SendLocation queues an m.location event with GeoURI ("geo:<lat>,<lon>") and body.
  func (a *Actions) SendLocation(ctx context.Context, roomID string, lat, lon float64, label, replyTo string) (SendResult, error)
  ```
- In `engine/internal/actions/linkpreview.go` and `actions.go`:
  - `SendMessageWith` gains `DisableLinkPreview *bool`.
  - When `DisableLinkPreview == nil || *DisableLinkPreview == true` (the default): sets `"com.beeper.linkpreviews": []` on outgoing `m.text` events that contain a URL, and makes **zero** network requests.
  - When `DisableLinkPreview != nil && *DisableLinkPreview == false`: if `WithLinkPreviewFetcher` is configured (defaulting to a local `http.Client` with a 3 s timeout, 256 KB HTML cap, and 2 MB `og:image` cap that refuses private/loopback IPs in production), parses `<meta property="og:*">`, stores any `og:image` in `media.Store` with `InspectImage`, and attaches `BeeperLinkPreviews` to the outgoing event.
- In `engine/internal/actions/actions.go` (`SendFileWith`):
  - Replace hardcoded `MaxFileBytes = 90 * 1024 * 1024` check with `maxSizeForKind(ctx, roomID, msgType)` which reads the bridge's `FileFeatures.MaxSize` when available (falling back to `MaxFileBytes` only when no login capability is present) and populates `BlurHash` + `IsAnimated` via `media.InspectImage` on outgoing images.
- In `NotificationCoordinator.swift` and `Notifier.swift`:
  - Extend `NotificationPlan` with `public let attachmentPath: String?` (populated from `event.thumbnailPath ?? event.mediaPath` when `event.kind` is `.image`, `.video`, or `.sticker` and `!event.viewOnce`).
  - In `Notifier.swift`, attach a cloned temp copy of `attachmentPath` via `UNNotificationAttachment(identifier:url:options:)` so macOS notifications display the media thumbnail.

**Steps:**
- [ ] **Step 1: Write failing tests in `send_test.go`, `conformance_test.go`, and `NotificationCoordinatorTests.swift`.**
  - `TestSendVoiceSelectsContainerPerBridgeCapabilities`: tests sending an `.m4a` voice note to a room requiring `audio/ogg; codecs=opus` (invoking a fake `ffmpeg` script to produce an OGG header and setting `MimeType: "audio/ogg; codecs=opus"`, `MSC3245Voice`, `MSC1767Audio.Waveform`), vs a room supporting `audio/mp4` (queued directly without `ffmpeg`), vs missing `ffmpeg` when required (returns `ErrVoiceTranscodeUnavailable`).
  - `TestSendLocationQueuesGeoURIAndRespectsCapability`: verifies `m.location` with `geo:37.7749,-122.4194` and rejection when `LocationMessage` is `CapLevelRejected`.
  - `TestSendMessageSuppressesLinkPreviewByDefaultAndFetchesOnlyWhenEnabled`: proves zero requests hit an `httptest.Server` when `DisableLinkPreview` is omitted or `true` (and `com.beeper.linkpreviews` is `[]` in the outbox), and verifies `og:title`/`og:description`/`og:image` extraction into `media.Store` when `DisableLinkPreview` is `false`.
  - `NotificationCoordinatorTests.testMediaNotificationIncludesAttachmentPathExceptViewOnce`: verifies `attachmentPath` is set for normal image/video events and `nil` for `viewOnce == true`.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/engine/internal/actions/... //apps/desktop/courier/engine/internal/rpc/... //apps/desktop/courier/app:CourierCoreTests` and confirm failure.**
- [ ] **Step 3: Implement `voice.go`, `linkpreview.go`, `actions.go` updates, `rpc/messages.go` handlers (`message.sendVoice`, `message.sendLocation`, `message.markPlayed`), and `NotificationCoordinator.swift` / `Notifier.swift`. Run `bazel run //:gazelle`.**
- [ ] **Step 4: Re-run all engine and Swift core tests and confirm `PASS`.**
- [ ] **Step 5: Commit Task 4.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add SendVoice, SendLocation, privacy-first link previews, and notification attachments" apps/desktop/courier/engine apps/desktop/courier/app`

---

### Task 5: Inline Images (`EnhancedImg`), BlurHash Placeholders, Consecutive Media Galleries (`GalleryGrouper`), and View-Once Viewer (`ViewLimitedMediaViewer`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/BlurHashDecoder.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/Timeline.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ThumbnailLoader.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/AttachmentChip.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/GalleryGridView.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/ViewOnceSheet.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationView.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/BlurHashDecoderTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/TimelineTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `BlurHashDecoder.swift`:
  ```swift
  public enum BlurHashDecoder {
      /// Decodes a BlurHash string into a small CGImage (default 32x32) for instant placeholder rendering.
      public static func decode(_ blurHash: String, width: Int = 32, height: Int = 32) -> CGImage?
  }
  ```
- In `Timeline.swift`:
  - Extend `Message` with `public let thumbnailPath: String?`, `public let blurhash: String?`, `public let durationMS: Int?`, `public let waveform: [Int]`, `public let isGIF: Bool`, `public let isAnimated: Bool`, `public let viewOnce: Bool`, `public let geoURI: String?`, `public let linkPreviews: [LinkPreviewItem]`, `public let played: Bool`.
  - Add `.location` to `MessageKind`.
  - Group 2–10 consecutive image/video messages from the same sender within 60 seconds that have no text caption (except optionally on the last item) into `public struct GalleryItem: Equatable, Sendable` on `Message` (`public let galleryItems: [GalleryItem]`, corresponding to `GalleryGrouper.tsx`).
- In `AttachmentChip.swift`, `GalleryGridView.swift`, and `ViewOnceSheet.swift`:
  - `EnhancedImageView` (`EnhancedImg.tsx`): renders the decoded `BlurHashDecoder` image while `ThumbnailLoader` loads the full image (`LoadingAttachment.tsx`, `FileRowSpinner.tsx`), renders looping muted auto-play for GIFs (`isGIF == true`), shows `ImageErrorCard` (`ImageError.tsx`) when the file is missing or unreadable, and shows a subtle badge when `TranscodedAttachment` metadata applies (`TranscodedAttachment.tsx`). Clicking invokes `onOpenLightbox(message.id)` instead of launching an external app.
  - `GalleryGridView` (`GalleryGrouper.tsx`, `GalleryVideoPoster.tsx`): 2–3 column adaptive grid for `message.galleryItems`, overlaying a play badge and duration pill on video poster tiles (`GalleryVideoPoster`).
  - `ViewOnceChip` and `ViewOnceSheet` (`ViewLimitedMediaViewer.tsx`): when `message.viewOnce == true`, the timeline bubble never renders an inline thumbnail; it shows a locked **View-once Photo / Video / Voice Note** pill (or **Opened** in muted text when `message.played == true`). Clicking an unopened view-once pill opens `ViewOnceSheet` (no Save, Copy, Share, or Quick Look controls) and calls `message.markPlayed` when dismissed.

**Steps:**
- [ ] **Step 1: Write failing tests in `BlurHashDecoderTests.swift`, `TimelineTests.swift`, and `ViewSnapshotTests.swift`.**
  - `BlurHashDecoderTests.testDecodesValidBlurHashAndRejectsInvalid`: asserts a 4x3 BlurHash decodes to a `32x32` `CGImage` and invalid strings return `nil`.
  - `TimelineTests.testGroupsConsecutiveSameSenderMediaIntoGallery`: feeds 4 consecutive image/video events from `@alice:courier.local` within 15 seconds and asserts they collapse into a single `Message` with `galleryItems.count == 4`, whereas a message from `@bob:courier.local` or a message with a caption in the middle breaks the run.
  - `TimelineTests.testViewOnceMessageTracksPlayedState`: verifies `viewOnce` and `played` propagation.
  - `ViewSnapshotTests.testEnhancedImageBlurHashErrorGalleryAndViewOnceLightAndDark`: renders `EnhancedImageView` (BlurHash loading state + loaded state + `ImageErrorCard`), a 3-item `GalleryGridView` with a `GalleryVideoPoster` tile, and `ViewOnceChip` (unopened + opened) + `ViewOnceSheet` in light and dark mode.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `BlurHashDecoder.swift`, `Timeline.swift` gallery grouping, `EnhancedImageView`, `GalleryGridView`, and `ViewOnceSheet`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 5.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add BlurHash placeholders, gallery grids, broken-image cards, and view-once viewer" apps/desktop/courier/app`

---

### Task 6: Inline Video Player (`BrandVideo`) and Floating Picture-in-Picture Window (`PictureInPictureBrowserWindow`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/Courier/InlineVideoPlayer.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/PictureInPictureController.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/AttachmentChip.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `InlineVideoPlayer.swift` (`BrandVideo.tsx`):
  ```swift
  struct InlineVideoPlayer: View {
      let messageID: String
      let roomID: String
      let mediaPath: String
      let thumbnailPath: String?
      let blurhash: String?
      let width: Int?
      let height: Int?
      let durationMS: Int?
      let isGIF: Bool
      let onPopOutPiP: () -> Void
      let onOpenLightbox: () -> Void
  }
  ```
  - Uses `AVPlayer` with a custom SwiftUI transport bar (Play/Pause, time elapsed / total duration, scrub slider, playback speed menu `0.25×`, `0.5×`, `1×`, `1.25×`, `1.5×`, `2×`, Mute toggle, **Picture in Picture** button, and **Expand** button). When `isGIF == true`, auto-plays muted in a loop with no transport bar unless hovered.
- In `PictureInPictureController.swift` (`PictureInPictureBrowserWindow.tsx`):
  ```swift
  @MainActor
  public final class PictureInPictureController: ObservableObject {
      public static let shared = PictureInPictureController()
      @Published public private(set) var activeItem: PiPVideoItem?
      public func show(_ item: PiPVideoItem)
      public func close()
  }
  ```
  - Hosts an always-on-top `NSPanel` (`level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`) with play/pause, scrub bar, **Return to Chat** button, and **Close** button so video keeps playing while you switch chats.

**Steps:**
- [ ] **Step 1: Write failing snapshot and controller tests in `ViewSnapshotTests.swift`.**
  - `ViewSnapshotTests.testInlineVideoPlayerAndPiPViewLightAndDark`: renders `InlineVideoPlayer` (paused with poster/duration and playing controls) and the `PictureInPictureView` panel content in light and dark mode, and verifies `PictureInPictureController.shared.show(...)` / `close()` state transitions.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `InlineVideoPlayer.swift` and `PictureInPictureController.swift`, and wire `.video` messages in `MessageBubble.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 6.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add inline BrandVideo player and floating Picture-in-Picture window" apps/desktop/courier/app`

---

### Task 7: Inline Voice-Note & Audio Player (`Audio`), Continuous Playback, and Persistent Floating Audio Bar (`GlobalAudioPlayer`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/AudioPlayerModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerPreferences.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ConversationModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/MessageMenu.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/VoiceNoteView.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/GlobalAudioPlayerBar.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageMenu.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessagesSettingsPane.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/AudioPlayerModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `ComposerPreferences.swift`:
  - Add `@Published public var autoPlayNextVoiceNote: Bool` (key `"courier.preferences.autoPlayNextVoiceNote"`, default `true`, matching `setting:general Automatically play the next voice note`).
- In `AudioPlayerModel.swift`:
  ```swift
  @MainActor
  public final class AudioPlayerModel: ObservableObject {
      public enum Speed: Double, CaseIterable, Sendable {
          case half = 0.5, one = 1.0, onePointFive = 1.5, two = 2.0
      }
      @Published public private(set) var currentTrack: Track?
      @Published public private(set) var isPlaying: Bool = false
      @Published public private(set) var progress: Double = 0
      @Published public private(set) var elapsedMS: Int = 0
      @Published public var speed: Speed = .one

      public func playOrPause(_ track: Track, queueInRoom: [Track])
      public func seek(to fraction: Double)
      public func cycleSpeed()
      public func stop()
      public func handleTrackFinished() async
  }
  ```
  - When a voice note starts or finishes, calls `conversation.markMediaPlayed(eventID:)` (`message.markPlayed`).
  - When `preferences.autoPlayNextVoiceNote` is `true` and a voice note finishes, automatically starts the next chronological voice note in `queueInRoom`.
  - When `currentTrack != nil` and its `roomID` is not the currently open chat (`!appModel.isOpen(roomID: track.roomID)`), `GlobalAudioPlayerBar` (`GlobalAudioPlayer.tsx`) appears at the top of `MainWindow` with sender name, chat title, play/pause, scrub bar, `0.5×–2×` speed pill, **Jump to Message**, and **Close** (`×`).
- In `MessageMenu.swift`: add `.markAsPlayed` (**Mark as played**) on unplayed voice notes.

**Steps:**
- [ ] **Step 1: Write failing tests in `AudioPlayerModelTests.swift` and `ViewSnapshotTests.swift`.**
  - `AudioPlayerModelTests.testPlaySeekSpeedCycleAndMarkPlayed`: injects a fake `AudioPlaybackBackend`, plays a track, cycles speed `1× -> 1.5× -> 2× -> 0.5× -> 1×`, seeks to `0.5`, and asserts `message.markPlayed` is sent to `TestEngineServer`.
  - `AudioPlayerModelTests.testContinuousPlaybackAdvancesToNextVoiceNoteWhenEnabled`: finishes track 1 with `autoPlayNextVoiceNote = true` and asserts track 2 starts automatically; repeats with `autoPlayNextVoiceNote = false` and asserts playback stops after track 1.
  - `AudioPlayerModelTests.testGlobalAudioBarShowsWhenSwitchingAwayFromPlayingRoom`: starts a voice note in `!r1:courier.local`, selects `!r2:courier.local`, and asserts `shouldShowGlobalBar == true`.
  - `ViewSnapshotTests.testVoiceNoteViewAndGlobalAudioPlayerBarLightAndDark`: snapshots `VoiceNoteView` (unplayed with waveform bars, playing at `1.5×` at 45% progress, and played) and `GlobalAudioPlayerBar` in light and dark mode.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `AudioPlayerModel.swift`, `VoiceNoteView.swift`, `GlobalAudioPlayerBar.swift`, the `Automatically play the next voice note` toggle in `MessagesSettingsPane.swift`, and `.markAsPlayed` in `MessageMenu.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 7.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add inline voice-note waveform player, continuous playback, and GlobalAudioPlayer" apps/desktop/courier/app`

---

### Task 8: Voice-Note Recording in the Composer (`⌘⇧A`, `BrandStopButton`, `/voice`, and Microphone Settings)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/VoiceRecorderModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerPreferences.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/EngineMessageSender.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationCommands.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessagesSettingsPane.swift`
- Modify: `apps/desktop/courier/app/Resources/Info.plist`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/VoiceRecorderModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `ComposerPreferences.swift`:
  - Add `@Published public var preferredMicrophoneUID: String` (key `"courier.preferences.preferredMicrophoneUID"`, default `""` = System Default, matching `setting:general Microphone`).
- In `VoiceRecorderModel.swift`:
  ```swift
  public struct AudioInputDevice: Equatable, Identifiable, Sendable {
      public let uid: String
      public let name: String
      public var id: String { uid }
  }

  public protocol VoiceRecordingBackend: Sendable {
      func availableDevices() -> [AudioInputDevice]
      func authorizationStatus() -> MicrophoneAuthStatus
      func requestAccess() async -> Bool
      func startRecording(deviceUID: String?) async throws -> URL
      func currentMeterLevel() -> Float // 0.0 ... 1.0
      func stopRecording() async throws -> RecordedVoiceNote
      func cancelRecording() async
  }

  @MainActor
  public final class VoiceRecorderModel: ObservableObject {
      public enum State: Equatable {
          case idle
          case recording(startedAt: Date, elapsedMS: Int, levels: [Int])
          case permissionDenied
          case failed(String)
      }
      @Published public private(set) var state: State = .idle
      @Published public private(set) var devices: [AudioInputDevice] = []
      public func start(preferredDeviceUID: String) async
      public func stopAndSend(using composer: ComposerModel) async
      public func cancel() async
  }
  ```
- In `ComposerView.swift` and `ConversationCommands.swift`:
  - Add microphone button and `⌘⇧A` shortcut (`hotkey Message: Record Audio`) plus `/voice` slash command in `ComposerModel.swift`.
  - While recording, replace the text area with the recording bar: pulsing red dot, `mm:ss` timer, live scrolling waveform bars (`0..100`), **Cancel** (`Esc` / trash button), `BrandStopButton` (`BrandStopButton.tsx`), and **Send** (`⏎`).
  - When microphone permission is `.denied`, show a non-blocking banner with **Open System Settings** (`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`).
- In `Info.plist`: add `NSMicrophoneUsageDescription` (`"Courier uses your microphone only when you record a voice note."`).

**Steps:**
- [ ] **Step 1: Write failing tests in `VoiceRecorderModelTests.swift` and `ViewSnapshotTests.swift`.**
  - `VoiceRecorderModelTests.testStartSampleWaveformStopAndSendVoice`: uses `FakeVoiceRecordingBackend` returning 20 meter samples and a temp `.m4a` file, calls `stopAndSend`, and verifies `message.sendVoice` is called with `duration_ms` and normalized `waveform` bars.
  - `VoiceRecorderModelTests.testCancelRecordingDeletesTempFileAndSendsNothing`: verifies `cancel()` removes the temp recording and does not call `message.sendVoice`.
  - `VoiceRecorderModelTests.testPermissionDeniedShowsNonBlockingStateWithoutCrashing`: injects `.denied` and asserts `state == .permissionDenied`.
  - `ViewSnapshotTests.testComposerVoiceRecordingBarAndMicrophonePickerLightAndDark`: snapshots `ComposerView` in `.recording` state (with `BrandStopButton` and waveform) and `.permissionDenied` state, plus the `Microphone` picker in `MessagesSettingsPane`, in light and dark mode.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Add `NSMicrophoneUsageDescription` to `Info.plist`, implement `VoiceRecorderModel.swift`, wire `ComposerModel.swift`, `EngineMessageSender.swift`, `ComposerView.swift`, `ConversationCommands.swift`, and `MessagesSettingsPane.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 8.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add composer voice-note recorder (Cmd+Shift+A), BrandStopButton, and microphone settings" apps/desktop/courier/app`

---

### Task 9: Inline PDFs (`PDFAttachment`, `PDF`), Rich File Cards (`FileAttachment`, `FilePlaceholder`), Drag-and-Drop Overlay (`FileDropOverlay`), and Attachment Downloads (`⌘O`, `⌘D`, Downloads Settings)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/AttachmentDownloader.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerPreferences.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/AttachmentChip.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/InlinePDFView.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/FileDropOverlayView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ComposerView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ConversationCommands.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MenuBar.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessagesSettingsPane.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/AttachmentDownloaderTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `ComposerPreferences.swift`:
  - Add `@Published public var downloadsDirectoryPath: String` (key `"courier.preferences.downloadsDirectoryPath"`, default `~/Downloads`, matching `setting:general Downloads location <path>`).
  - Add `@Published public var alwaysAskWhereToSaveFiles: Bool` (key `"courier.preferences.alwaysAskWhereToSaveFiles"`, default `false`, matching `setting:general Always ask where to save files before downloading`).
- In `AttachmentDownloader.swift`:
  ```swift
  @MainActor
  public final class AttachmentDownloader {
      public init(preferences: ComposerPreferences, promptSavePanel: @escaping (String, URL) -> URL? = AttachmentDownloader.defaultSavePanel)
      /// Saves `sourcePath` with `suggestedName`, stamping `kLSQuarantineTypeOtherDownload` and deduplicating filenames (`report (1).pdf`).
      public func download(sourcePath: String, suggestedName: String?) throws -> URL?
  }
  ```
- In `InlinePDFView.swift` (`PDFAttachment.tsx`, `PDF.tsx`):
  - Renders inline `PDFDocument` pages using `PDFKit` (`PDFPage.thumbnail(of:for:)` for deterministic rendering in both live views and snapshot tests), with a header showing filename, byte size, `Page X of N`, **Previous Page** / **Next Page** buttons, **Open**, and **Download** (`⌘D`).
- In `AttachmentChip.swift` (`FileAttachment.tsx`, `FilePlaceholder.tsx`, `PendingAttachments.tsx`):
  - Rich file card with category icon (`Audio`, `PDF`, `Text`, `Archive`, `Document` — `FilePlaceholder.tsx`), filename, human byte size, **Quick Look** (`Space`), **Open**, and **Download** button.
  - `PendingAttachmentsStrip` (`PendingAttachments.tsx`) in `ComposerView.swift` shows thumbnail previews, byte sizes, per-network `FileFeatures.MaxSize` warnings before send, and remove (`×`) buttons.
- In `FileDropOverlayView.swift` (`FileDropOverlay.tsx`):
  - Dragging files over `ConversationView` displays a full-pane drop target: **"Drop files to attach to your message"** and **"Hold ⇧ Shift to send immediately"**.
- In `MenuBar.swift` and `ConversationCommands.swift`:
  - Add `File ▸ Open…` (`⌘O`, `menu:File Open…`, `hotkey Chat: Send File`) opening the file picker to attach files to the active composer.
  - Add `⌘D` (`hotkey Download Attachments`) downloading all attachments on the selected message (or the active lightbox item).

**Steps:**
- [ ] **Step 1: Write failing tests in `AttachmentDownloaderTests.swift` and `ViewSnapshotTests.swift`.**
  - `AttachmentDownloaderTests.testDownloadsToConfiguredFolderWithQuarantineAndDeduplicatesName`: writes two files named `spec.pdf` with `alwaysAskWhereToSaveFiles = false`, asserts they land at `<tmp>/spec.pdf` and `<tmp>/spec (1).pdf`, and verifies `LSCopyItemAttribute` has `kLSQuarantineTypeOtherDownload`.
  - `AttachmentDownloaderTests.testAlwaysAskPromptsSavePanelAndHonorsCancel`: sets `alwaysAskWhereToSaveFiles = true`, injects a fake `promptSavePanel` returning `nil` (cancel) then a custom path, and verifies behavior.
  - `ViewSnapshotTests.testInlinePDFViewFilePlaceholderAndDropOverlayLightAndDark`: generates a 2-page PDF with `CGContext`, renders `InlinePDFView` on Page 1 of 2 and Page 2 of 2, `FileAttachmentChip` (`Audio`, `Archive`, `Text` placeholders), `PendingAttachmentsStrip` (including an over-limit size warning), and `FileDropOverlayView` (normal + Shift-held) in light and dark mode.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `AttachmentDownloader.swift`, `InlinePDFView.swift`, `FileDropOverlayView.swift`, `AttachmentChip.swift` updates, `MenuBar.swift` (`File ▸ Open…` `⌘O`), `ConversationCommands.swift` (`⌘D`), and Downloads settings in `MessagesSettingsPane.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 9.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add inline PDF viewer, rich file cards, FileDropOverlay, and Cmd+O / Cmd+D downloads" apps/desktop/courier/app`

---

### Task 10: Inline Location Cards (`Location`), Link Preview Cards, and Privacy-Gated External Embeds (`MessageIFrame`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/GeoURIParser.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerPreferences.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/ComposerModel.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/LocationCardView.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/LinkPreviewCardView.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessageBubble.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MessagesSettingsPane.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/GeoURIParserTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/ComposerModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `GeoURIParser.swift`:
  ```swift
  public struct GeoCoordinate: Equatable, Sendable {
      public let latitude: Double
      public let longitude: Double
      public let label: String?
      public static func parse(_ geoURI: String, fallbackLabel: String? = nil) -> GeoCoordinate?
      public var appleMapsURL: URL { ... }   // https://maps.apple.com/?ll=<lat>,<lon>&q=<label>
      public var googleMapsURL: URL { ... }  // https://www.google.com/maps/search/?api=1&query=<lat>,<lon>
  }
  ```
- In `LocationCardView.swift` (`Location.tsx`):
  - Renders a completely offline coordinate grid + pin canvas (no Apple/Google tile server requests on render!) with formatted `lat, lon`, optional label, and three action buttons: **Open in Apple Maps**, **Open in Google Maps**, and **Copy Location**.
  - In `ComposerModel.swift`, `/location <lat>,<lon> [label]` sends an `m.location` via `message.sendLocation` when `features.locationSupported` is `true`.
- In `ComposerPreferences.swift`:
  - Add `@Published public var disableOutgoingLinkPreviews: Bool` (key `"courier.preferences.disableOutgoingLinkPreviews"`, default `true`, matching `setting:appearance Disable link previews in outgoing messages`).
  - Add `@Published public var loadExternalEmbedsAutomatically: Bool` (key `"courier.preferences.loadExternalEmbedsAutomatically"`, default `false`, matching `setting:appearance Load external embeds automatically`).
- In `LinkPreviewCardView.swift` (`MessageIFrame.tsx`):
  - Renders each `LinkPreviewItem` from `message.linkPreviews` (domain header, bold `title`, 2-line `description`, and local `imagePath` thumbnail via `ThumbnailLoader`).
  - When a URL matches an embeddable media link (YouTube/Vimeo/Spotify/Loom) and `loadExternalEmbedsAutomatically == false`, renders a local `EmbedConsentCard` (`MessageIFrame.tsx`): **"External embed from <host> is blocked to protect your IP address"** with a **Load Embed** button that loads a sandboxed `WKWebView` (`configuration.websiteDataStore = .nonPersistent()`) only for that single message ID when clicked.

**Steps:**
- [ ] **Step 1: Write failing tests in `GeoURIParserTests.swift`, `ComposerModelTests.swift`, and `ViewSnapshotTests.swift`.**
  - `GeoURIParserTests.testParsesGeoURIWithUncertaintyAndParameters`: parses `"geo:37.7749,-122.4194;u=15"`, verifies coordinates, Apple Maps URL, Google Maps URL, and rejects out-of-range lat/lon.
  - `ComposerModelTests.testOutgoingSendPassesDisableLinkPreviewFromPreferences`: verifies `disable_link_preview: true` is sent by default and `false` when the user unchecks `Disable link previews in outgoing messages`.
  - `ViewSnapshotTests.testLocationCardLinkPreviewAndEmbedConsentLightAndDark`: snapshots `LocationCardView`, `LinkPreviewCardView` (with and without local thumbnail), and `EmbedConsentCard` in light and dark mode.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `GeoURIParser.swift`, `LocationCardView.swift`, `LinkPreviewCardView.swift`, preference toggles in `MessagesSettingsPane.swift`, and wire `MessageBubble.swift` and `ComposerModel.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 10.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add inline Location cards, link previews, and privacy-gated external embeds" apps/desktop/courier/app`

---

### Task 11: Full-Window Attachment Lightbox (`AttachmentCarousel`) and Media Viewer Window (`MediaViewerBrowserWindow`, `MediaWithSender`)

**Files:**
- Create: `apps/desktop/courier/app/Sources/CourierCore/AttachmentCarouselModel.swift`
- Create: `apps/desktop/courier/app/Sources/CourierCore/MediaViewerModel.swift`
- Modify: `apps/desktop/courier/app/Sources/CourierCore/CommandSet.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/AttachmentCarouselOverlay.swift`
- Create: `apps/desktop/courier/app/Sources/Courier/MediaViewerWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/MainWindow.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/ChatInfoPane.swift`
- Modify: `apps/desktop/courier/app/Sources/Courier/App.swift`
- Create: `apps/desktop/courier/app/Tests/CourierCoreTests/MediaViewerModelTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierCoreTests/CommandSetTests.swift`
- Modify: `apps/desktop/courier/app/Tests/CourierViewTests/ViewSnapshotTests.swift`

**Interfaces:**
- In `AttachmentCarouselModel.swift` (`AttachmentCarousel.tsx`):
  ```swift
  @MainActor
  public final class AttachmentCarouselModel: ObservableObject {
      @Published public private(set) var items: [CarouselItem] = []
      @Published public private(set) var currentIndex: Int = 0
      @Published public var zoomScale: Double = 1.0       // 0.5 ... 5.0
      @Published public var rotationDegrees: Int = 0      // 0, 90, 180, 270
      @Published public var isFlippedHorizontally: Bool = false
      @Published public var isFlippedVertically: Bool = false

      public func open(items: [CarouselItem], selectedEventID: String)
      public func close()
      public func next()
      public func previous()
      public func zoomIn()
      public func zoomOut()
      public func resetTransform()
      public func rotateClockwise()
      public func flipHorizontal()
      public func flipVertical()
  }
  ```
  - `AttachmentCarouselOverlay` renders a full-window dark backdrop over `MainWindow` with:
    - Top bar: sender avatar + name, timestamp, filename, **Go to Message**, **React**, **Reply**, **Copy Image** (`⌘C`), **Quick Look** (`Space`), **Download** (`D` / `⌘D`), and **Close** (`Esc`).
    - Center stage: zoomable/pannable image or video with **Previous** (`←`) / **Next** (`→`) arrows.
    - Bottom bar: transform controls (`Zoom Out -`, `100%`, `Zoom In +`, `Rotate 90°`, `Flip H`, `Flip V`) and thumbnail filmstrip of all media in the room.
- In `MediaViewerModel.swift` (`MediaViewerBrowserWindow.tsx`, `MediaWithSender.tsx`):
  ```swift
  @MainActor
  public final class MediaViewerModel: ObservableObject {
      public enum Tab: String, CaseIterable, Sendable { case media = "Media", links = "Links", docs = "Docs" }
      public enum SentByFilter: String, CaseIterable, Sendable { case all = "All", you = "You", others = "Others" }
      public enum SortOrder: String, CaseIterable, Sendable { case newest = "Newest", oldest = "Oldest" }

      @Published public var tab: Tab = .media
      @Published public var sentBy: SentByFilter = .all
      @Published public var sortOrder: SortOrder = .newest
      @Published public var query: String = ""
      @Published public private(set) var items: [MediaHit] = []
      @Published public var selectedEventIDs: Set<String> = []
      public func refresh() async
      public func toggleSelected(_ eventID: String)
      public func deleteSelected(forEveryone: Bool) async
  }
  ```
  - Queries `search.query` (`sections: ["media"]`, `kinds: ["image", "video", "sticker"]` for **Media**, `["link"]` for **Links**, `["file", "audio"]` for **Docs**, scoped to `appModel.openRoomIDs` when opened from a chat or all rooms when opened globally), filters by `SentByFilter` (`from_me`), sorts by `SortOrder`, and renders `MediaWithSender` tiles with multi-select **Download Selected**, **Delete Selected**, and **Go to Message**.
- In `CommandSet.swift`: register `command Media viewer` (`id: "media.viewer"`, title: `"Media viewer"`), opening the `"media-viewer"` window (`MediaViewerWindow.swift`), and wire **See All** in `ChatInfoPane`'s Shared Media / Files / Links sections to open `MediaViewerWindow` on the matching tab.

**Steps:**
- [ ] **Step 1: Write failing tests in `MediaViewerModelTests.swift`, `CommandSetTests.swift`, and `ViewSnapshotTests.swift`.**
  - `MediaViewerModelTests.testTabsSentBySortSearchAndMultiSelect`: verifies switching tabs (`Media` / `Links` / `Docs`), filtering `SentByFilter` (`All`, `You`, `Others`), toggling `SortOrder` (`Newest` vs `Oldest`), caption query filtering, and `AttachmentCarouselModel` transform controls (`zoomIn`, `rotateClockwise`, `flipHorizontal`, `next`, `previous`).
  - `CommandSetTests.testMediaViewerCommandRegistered`: asserts `"Media viewer"` is present in `CommandSet` and invokes `openMediaViewer`.
  - `ViewSnapshotTests.testAttachmentCarouselAndMediaViewerWindowLightAndDark`: snapshots `AttachmentCarouselOverlay` (with filmstrip and transform bar) and `MediaViewerView` (**Media** tab with `MediaWithSender` tiles, **Links** tab, and **Docs** tab with multi-selection bar) in light and dark mode.
- [ ] **Step 2: Run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm failure.**
- [ ] **Step 3: Implement `AttachmentCarouselModel.swift`, `MediaViewerModel.swift`, `AttachmentCarouselOverlay.swift`, `MediaViewerWindow.swift`, `CommandSet.swift`, `MainWindow.swift`, `ChatInfoPane.swift`, and `App.swift`.**
- [ ] **Step 4: Re-run `bazel test //apps/desktop/courier/app:CourierCoreTests //apps/desktop/courier/app:CourierViewTests` and confirm `PASS`.**
- [ ] **Step 5: Commit Task 11.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "feat(courier): add AttachmentCarousel lightbox and MediaViewerBrowserWindow" apps/desktop/courier/app`

---

### Task 12: Final Checks and `m4-acceptance.md` 4.5b Update

**Files:**
- Modify: `apps/desktop/courier/docs/m4-acceptance.md`

**Steps:**
- [ ] **Step 1: Update `apps/desktop/courier/docs/m4-acceptance.md` by adding `## Part 4.5b — Rich Media Playback, Capture, Previews, and Media Viewer` (listing every `anchor` + `item` row from `### Covered in Milestone 4.5b (this plan — 35 rows)` below under `Keys`, `Settings`, `Menus`, `Components`, and `Commands`) and updating the remaining `Carried to Milestone 4.5c` list (10 rows).**
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
  - Expected: all engine Go tests, protocol conformance tests, `CourierCoreTests` (including `testNoDirectSelectedRoomIDComparisonsInSources`), `CourierViewTests` (light + dark PNG snapshots), macOS app bundle build, lint, and secret scan exit `0`.
- [ ] **Step 3: Inspect the generated light and dark PNG snapshots in `bazel-testlogs/apps/desktop/courier/app/CourierViewTests/test.outputs/` to confirm layout, contrast, and alignment.**
- [ ] **Step 4: Commit the acceptance doc update.**
  - Run: `bazel run //tools/git:commit -- --agent wren -m "docs(courier): record milestone 4.5b acceptance checklist" apps/desktop/courier/docs/m4-acceptance.md`

---

### Task 13: Owner's By-Hand Day on Real Accounts

**Files:**
- Modify: `apps/desktop/courier/docs/m4-acceptance.md`

**Steps:**
- [ ] **Step 1: Launch the built app bundle (`bazel build --config=macos-app //apps/desktop/courier/app:Courier`) against your live `courier.db` and walk through these live checks:**
  1. **Images, BlurHash, and galleries:** Receive and send single photos and a burst of 3+ photos across WhatsApp, Signal, and Telegram. Verify the BlurHash placeholder, the multi-photo gallery grid, and clicking a photo to open `AttachmentCarousel` (zoom, rotate 90°, flip, `←`/`→` navigation, `Space` Quick Look, `⌘C` copy, `D` download).
  2. **View-once media:** Send a view-once photo or voice note from your phone on Signal or Telegram to Courier. Verify no inline preview is shown in the timeline, click to open `ViewLimitedMediaViewer`, close it, and verify it transitions to **Opened** and cannot be reopened or saved.
  3. **Inline video and Picture-in-Picture:** Play an `.mp4` video inline (`0.5×–2×` speed, scrub), click **Picture in Picture**, switch to another chat, and confirm the floating PiP window stays playing on top.
  4. **Voice notes and continuous playback:** Play a sequence of two consecutive voice notes at `1.5×`. Confirm the waveform scrubs smoothly, the first voice note marks itself played and automatically starts the second voice note, and switching chats docks `GlobalAudioPlayer` at the top of the window.
  5. **Voice-note recording (`⌘⇧A`):** Select your microphone in **Settings ▸ Messages**, press `⌘⇧A`, record a short voice note, verify the live waveform and `BrandStopButton`, send it to a WhatsApp chat (`audio/ogg; codecs=opus`) and a Signal/Telegram chat (`audio/mp4` / `audio/aac`), and confirm it arrives as a native voice note on the phone.
  6. **PDFs, files, drag-and-drop, and downloads (`⌘O`, `⌘D`):** Drag a multi-page PDF into a chat (and `Shift`-drop another file to send immediately). Verify the inline `PDF` page stepper (**Previous Page** / **Next Page**), press `⌘O` to attach a file, and press `⌘D` on an attachment to verify both automatic saving to `Downloads location` and prompting when `Always ask where to save files before downloading` is ticked.
  7. **Locations, link previews, and embeds:** View a shared location card and click **Open in Apple Maps** / **Open in Google Maps** / **Copy Location**. Send a URL with `Disable link previews in outgoing messages` on (confirm no preview is attached or unfurled), then turn it off and send a URL (confirm the preview card attaches). Click **Load Embed** on a video link to confirm click-to-load consent.
  8. **Media Viewer window:** Open the command bar (`⌘K`), run `Media viewer`, and verify the **Media**, **Links**, and **Docs** tabs, **Sent By** (`All` / `You` / `Others`), **Sort by** (`Newest` / `Oldest`), caption search, and multi-select **Download** / **Go to Message**.

---

## Scope of Milestone 4.5c (Follow-Up Plan — 10 Inventory Rows)

Milestone 4.5c will cover the composer emoji, emoticon, sticker, and GIF authoring tools in a small self-contained plan (~6 tasks):
- **Emoji autocomplete & emoticon replacement:** `Autocomplete.tsx` (`:` shortcode popover in the composer), `Emoji.tsx` and `EmojiItem.tsx` (composer `+` menu and emoji grid cells), `setting:general Enable emoji autocomplete`, and `setting:general Disable automatic replacement of emoticons with emojis` (`:)` -> `🙂` on word boundary unless disabled).
- **Sticker picker (`⌘⌥⇧S`):** `StickerPicker.tsx` and `hotkey Message: Send Sticker` browsing locally imported sticker packs (`<datadir>/stickers/`), sending `m.sticker` on WhatsApp, Signal, and Telegram (and `m.image` on Slack per `mautrix-slack/pkg/msgconv/from-matrix.go:68-71`; hidden on Google Messages where `CapMsgSticker` is absent).
- **GIF picker (`⌘⇧G`):** `GifPicker.tsx`, `hotkey Message: Send GIF`, `/gif` slash command, and `setting:general Automatically send GIFs after selection` (attaching to draft vs sending immediately, using local GIF files in 4.5c and an opt-in search provider in 4.7).

---

## Ledger Coverage (`docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv`)

### Covered in Milestone 4.5b (this plan — 35 rows)
- `component AttachmentCarousel.tsx` → **Task 11** (`AttachmentCarouselOverlay` full-window lightbox with zoom, pan, rotate, flip, Quick Look, copy, download)
- `component Audio.tsx` → **Task 7** (`VoiceNoteView` inline waveform player with `0.5×–2×` speed and played state)
- `component BrandStopButton.tsx` → **Task 8** (`BrandStopButton` stop-recording control in `ComposerView`)
- `component BrandVideo.tsx` → **Task 6** (`InlineVideoPlayer` inline video transport and speed controls)
- `component EnhancedImg.tsx` → **Task 5** (`EnhancedImageView` inline image with `BlurHashDecoder` placeholder)
- `component FileAttachment.tsx` → **Task 9** (`FileAttachmentChip` downloadable file card with size, Quick Look, and `⌘D`)
- `component FileDropOverlay.tsx` → **Task 9** (`FileDropOverlayView` drag-and-drop overlay with Shift-to-send)
- `component FilePlaceholder.tsx` → **Task 9** (typed Audio / PDF / Text / Archive / Document placeholder cards in `AttachmentChip.swift`)
- `component FileRowSpinner.tsx` → **Task 5** (attachment loading spinner in `AttachmentChip.swift`)
- `component GalleryGrouper.tsx` → **Task 5** (`GalleryGridView` grouping consecutive same-sender image/video attachments)
- `component GalleryVideoPoster.tsx` → **Task 5** (video poster frame with duration and play overlay in `GalleryGridView`)
- `component GlobalAudioPlayer.tsx` → **Task 7** (`GlobalAudioPlayerBar` persistent audio bar across chat switches)
- `component ImageError.tsx` → **Task 5** (`ImageErrorCard` broken-image fallback card)
- `component LoadingAttachment.tsx` → **Task 5** (BlurHash + skeleton placeholder for loading attachments)
- `component Location.tsx` → **Task 10** (`LocationCardView` with offline coordinate pin, Apple Maps, Google Maps, and Copy Location)
- `component MediaViewerBrowserWindow.tsx` → **Task 11** (`MediaViewerWindow` with **Media**, **Links**, **Docs** tabs, **Sent By** filter, sort, and search)
- `component MediaWithSender.tsx` → **Task 11** (media tile with sender badge and timestamp in `MediaViewerWindow`)
- `component MessageIFrame.tsx` → **Task 10** (`EmbedConsentCard` and sandboxed click-to-load `WKWebView` in `LinkPreviewCardView.swift`)
- `component PDF.tsx` → **Task 9** (`InlinePDFView` paged `PDFKit` document viewer)
- `component PDFAttachment.tsx` → **Task 9** (PDF card header with page stepper, Open, and Download in `InlinePDFView.swift`)
- `component PendingAttachments.tsx` → **Task 9** (`PendingAttachmentsStrip` in `ComposerView.swift` with per-network size checks)
- `component PictureInPictureBrowserWindow.tsx` → **Task 6** (`PictureInPictureController` floating `NSPanel` video window)
- `component TranscodedAttachment.tsx` → **Task 5** (transcoded media indicator badge in `AttachmentChip.swift`)
- `component ViewLimitedMediaViewer.tsx` → **Task 5** (`ViewOnceChip` and `ViewOnceSheet` for view-once photos, videos, and voice notes)
- `command Media viewer` → **Task 11** (registered in `CommandSet.swift`, opens `MediaViewerWindow`)
- `hotkey Chat: Send File` → **Task 9** (`⌘O` attach file shortcut in `ConversationCommands.swift`)
- `hotkey Download Attachments` → **Task 9** (`⌘D` download attachment shortcut in `ConversationCommands.swift`)
- `hotkey Message: Record Audio` → **Task 8** (`⌘⇧A` start/stop voice-note recording in `ConversationCommands.swift`)
- `setting:appearance Disable link previews in outgoing messages` → **Tasks 4, 10** (toggle in `MessagesSettingsPane.swift` + `disable_link_preview` in `message.send`)
- `setting:appearance Load external embeds automatically` → **Task 10** (toggle in `MessagesSettingsPane.swift` gating `EmbedConsentCard`)
- `setting:general Always ask where to save files before downloading` → **Task 9** (toggle in `MessagesSettingsPane.swift` + `AttachmentDownloader`)
- `setting:general Automatically play the next voice note` → **Task 7** (toggle in `MessagesSettingsPane.swift` + `AudioPlayerModel`)
- `setting:general Downloads location <path>` → **Task 9** (folder picker in `MessagesSettingsPane.swift` + `AttachmentDownloader`)
- `setting:general Microphone` → **Task 8** (input device picker in `MessagesSettingsPane.swift` + `VoiceRecorderModel`)
- `menu:File Open…` → **Task 9** (`File ▸ Open…` `⌘O` menu command in `MenuBar.swift`)

### Carried to Milestone 4.5c (Emoji, Emoticons, Stickers, and GIFs — 10 rows)
- `component Autocomplete.tsx` (composer `:` emoji autocomplete popover)
- `component Emoji.tsx` (composer plus-menu media/emoji items)
- `component EmojiItem.tsx` (emoji picker cell)
- `component GifPicker.tsx` (composer GIF picker UI)
- `component StickerPicker.tsx` (composer sticker picker)
- `hotkey Message: Send GIF` (`⌘⇧G` open GIF picker)
- `hotkey Message: Send Sticker` (`⌘⌥⇧S` open sticker picker)
- `setting:general Automatically send GIFs after selection` (send picked GIF immediately vs attach to draft)
- `setting:general Disable automatic replacement of emoticons with emojis` (toggle `:)` -> `🙂` replacement in composer)
- `setting:general Enable emoji autocomplete` (toggle `:` emoji autocomplete in composer)

---

## Appendix: Bridge Verification Commands (`~/go/pkg/mod`)

Every row in the Per-Network Capability Table was verified against the pinned modules in `~/go/pkg/mod` with the following `grep` commands:

```sh
# 1. Shared mautrix event & capability types (maunium.net/go/mautrix@v0.31.0)
grep -n "CapMsgVoice\|CapMsgGIF\|CapMsgSticker\|type FileFeatures" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/capabilities.go
grep -n "MsgImage\|MsgLocation\|MsgVideo\|MsgAudio\|MsgFile\|type FileInfo\|BeeperLinkPreviews\|MSC1767Audio\|MSC3245Voice" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/message.go
grep -n "type MSC1767Audio\|type MSC3245Voice" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/audio.go
grep -n "type LinkPreview\|type BeeperLinkPreview" ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/beeper.go

# 2. Per-bridge FileFeatures, MaxFileSize, Voice, GIF, Sticker, Location, LinkPreviews
grep -n "WAMaxFileSize\|MaxFileSize\|MsgImage\|MsgVideo\|MsgAudio\|MsgFile\|CapMsgVoice\|CapMsgGIF\|CapMsgSticker\|LocationMessage\|SendURLPreviews" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/connector/capabilities.go \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/connector/capabilities.go \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/connector/capabilities.go \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/connector/capabilities.go \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/connector/capabilities.go

# 3. Voice notes (MSC3245Voice / MSC1767Audio / waveform / MIME conversion)
grep -rn "MSC3245Voice\|MSC1767Audio\|Waveform\|slack_audio\|VOICE_MESSAGE" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/

# 4. Voice-note played receipts (confirming unverified / not bridged across all 5 bridges)
grep -rn "ReceiptTypePlayed\|played" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/

# 5. GIFs & Stickers conversion
grep -rn "MauGIF\|GifPlayback\|EventSticker" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/

# 6. View-once media handling
grep -rn "ViewOnce\|IsViewOnce\|DisappearViewOnce\|DisableViewOnce\|2147483647" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/

# 7. Location messages (MsgLocation / GeoURI)
grep -rn "MsgLocation\|GeoURI\|LocationFormat" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/

# 8. Link previews (BeeperLinkPreview / BeeperLinkPreviews / NoWebpage / DisableLinkUnfurl)
grep -rn "BeeperLinkPreview\|NoWebpage\|DisableLinkUnfurl" \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/

# 9. BlurHash preservation
grep -rn "Blurhash\|AnoaBlurhash\|blurhash" \
  ~/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/event/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-whatsapp@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-signal@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-telegram@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-gmessages@v0.2609.0/pkg/ \
  ~/go/pkg/mod/go.mau.fi/mautrix-slack@v0.2609.1/pkg/
```
