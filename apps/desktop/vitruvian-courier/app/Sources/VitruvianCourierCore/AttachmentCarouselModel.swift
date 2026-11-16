// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Returns true only when `path` is a local filesystem path (never a remote `http://`, `https://`, or `mxc://` URL).
public func isLocalMediaStorePath(_ path: String) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mxc://") {
        return false
    }
    return trimmed.hasPrefix("/")
}

/// Returns true when `path` is a non-empty remote URL (`http://`, `https://`, `mxc://`) or non-local path.
public func isRemoteMediaURL(_ path: String) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return !isLocalMediaStorePath(trimmed)
}

/// One image or video item shown in `AttachmentCarouselOverlay`.
///
/// Only non-view-once images and videos belong in the viewer (matching Chat Info's **Shared Media** and excluding
/// link previews, stickers, files, voice notes, and removed media). Local paths are sanitized through
/// `isLocalMediaStorePath`; an item whose local file is not yet downloaded keeps `mediaPath == ""` so the viewer
/// count matches Chat Info and its thumbnail renders a neutral placeholder instead of blank.
public struct CarouselItem: Identifiable, Equatable, Sendable {
    public var id: String { eventID }
    public let eventID: String
    public let roomID: String
    public let kind: MessageKind
    public let mediaPath: String
    public let thumbnailPath: String
    public let fileName: String
    public let mimeType: String
    public let width: Int?
    public let height: Int?
    public let blurhash: String
    public let durationMS: Int?
    public let isGIF: Bool
    public let sender: String
    public let senderName: String
    public let senderAvatarPath: String
    public let mine: Bool
    public let ts: Int64
    public let caption: String
    public let viewOnce: Bool

    public init(
        eventID: String,
        roomID: String,
        kind: MessageKind = .image,
        mediaPath: String,
        thumbnailPath: String = "",
        fileName: String = "",
        mimeType: String = "",
        width: Int? = nil,
        height: Int? = nil,
        blurhash: String = "",
        durationMS: Int? = nil,
        isGIF: Bool = false,
        sender: String = "",
        senderName: String = "",
        senderAvatarPath: String = "",
        mine: Bool = false,
        ts: Int64 = 0,
        caption: String = "",
        viewOnce: Bool = false
    ) {
        self.eventID = eventID
        self.roomID = roomID
        self.kind = kind
        self.mediaPath = mediaPath
        self.thumbnailPath = thumbnailPath.isEmpty ? mediaPath : thumbnailPath
        self.fileName = fileName
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.blurhash = blurhash
        self.durationMS = durationMS
        self.isGIF = isGIF
        self.sender = sender
        self.senderName = senderName
        self.senderAvatarPath = senderAvatarPath
        self.mine = mine
        self.ts = ts
        self.caption = caption
        self.viewOnce = viewOnce
    }

    /// Creates a `CarouselItem` from a `TimelineMessage` if it is a non-view-once image or video.
    public init?(message: TimelineMessage) {
        guard !message.viewOnce,
              !message.showsMediaRemovedPlaceholder,
              message.kind == .image || message.kind == .video
        else {
            return nil
        }
        let thumb = message.thumbnailPath ?? ""
        let resolvedMediaPath = isLocalMediaStorePath(message.mediaPath) ? message.mediaPath : ""
        let resolvedThumb = isLocalMediaStorePath(thumb) ? thumb : resolvedMediaPath
        let captionText = (message.body != message.fileName) ? message.body : ""
        self.init(
            eventID: message.id,
            roomID: message.roomID,
            kind: message.kind,
            mediaPath: resolvedMediaPath,
            thumbnailPath: resolvedThumb,
            fileName: message.fileName.isEmpty ? message.body : message.fileName,
            mimeType: message.mimeType,
            width: message.width,
            height: message.height,
            blurhash: message.blurhash ?? "",
            durationMS: message.durationMS,
            isGIF: message.isGIF,
            sender: message.sender,
            senderName: message.senderName,
            senderAvatarPath: message.senderAvatarPath,
            mine: message.mine,
            ts: message.ts,
            caption: captionText,
            viewOnce: false
        )
    }

    /// Creates a `CarouselItem` from a raw `Event` (such as `RoomInfoResult.sharedMedia`) if it is a non-view-once
    /// image or video (`m.image` / `m.video`). Strictly excludes link previews (`m.text`), stickers, files, and audio.
    public init?(event: Event) {
        guard event.type == "m.room.message",
              event.viewOnce != true,
              case let .object(dict) = event.content,
              dict["com.courier.media_removed"] != .bool(true),
              let msgtype = dict["msgtype"]?.stringValue
        else {
            return nil
        }
        let kind: MessageKind
        switch msgtype {
        case "m.image":
            kind = .image
        case "m.video":
            kind = .video
        default:
            return nil
        }
        let rawURL = (dict["url"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMediaPath = isLocalMediaStorePath(event.mediaPath) ? event.mediaPath : ""
        let thumb = event.thumbnailPath ?? ""
        let resolvedThumb = isLocalMediaStorePath(thumb) ? thumb : resolvedMediaPath
        guard !resolvedMediaPath.isEmpty || !resolvedThumb.isEmpty || !rawURL.isEmpty else {
            return nil
        }

        let body = dict["body"]?.stringValue ?? ""
        let filename = dict["filename"]?.stringValue
        let resolvedFileName = (filename?.isEmpty == false) ? filename! : body
        let captionText = (filename != nil && filename != body) ? body : ""
        let info = dict["info"]
        let mime = info?["mimetype"]?.stringValue ?? (kind == .video ? "video/mp4" : "image/jpeg")
        let width = info?["w"]?.integerValue.map(Int.init)
        let height = info?["h"]?.integerValue.map(Int.init)
        let blurhash = event.blurhash
            ?? info?["xyz.amorgan.blurhash"]?.stringValue
            ?? info?["blurhash"]?.stringValue
            ?? ""
        let durationMS = event.durationMS.map(Int.init) ?? info?["duration"]?.integerValue.map(Int.init)
        let isGIF = event.isGIF
            ?? (mime.caseInsensitiveCompare("image/gif") == .orderedSame
                || info?["fi.mau.gif"] == .bool(true)
                || dict["fi.mau.gif"] == .bool(true))

        self.init(
            eventID: event.eventID,
            roomID: event.roomID,
            kind: kind,
            mediaPath: resolvedMediaPath,
            thumbnailPath: resolvedThumb,
            fileName: resolvedFileName,
            mimeType: mime,
            width: width,
            height: height,
            blurhash: blurhash,
            durationMS: durationMS,
            isGIF: isGIF,
            sender: event.sender,
            senderName: event.senderName,
            senderAvatarPath: event.senderAvatarPath,
            mine: event.mine,
            ts: event.ts,
            caption: captionText,
            viewOnce: false
        )
    }

    /// Creates a `CarouselItem` from a `MediaHit` if it is a non-view-once image or video.
    public init?(hit: MediaHit) {
        guard !hit.viewOnce,
              hit.mediaPath.isEmpty || isLocalMediaStorePath(hit.mediaPath)
        else {
            return nil
        }
        let messageKind: MessageKind
        switch hit.kind {
        case .image:
            messageKind = .image
        case .video:
            messageKind = .video
        default:
            return nil
        }
        let resolvedMediaPath = isLocalMediaStorePath(hit.mediaPath) ? hit.mediaPath : ""
        self.init(
            eventID: hit.eventID,
            roomID: hit.roomID,
            kind: messageKind,
            mediaPath: resolvedMediaPath,
            thumbnailPath: resolvedMediaPath,
            fileName: hit.fileName,
            mimeType: messageKind == .video ? "video/mp4" : "image/jpeg",
            sender: hit.sender,
            senderName: hit.senderName,
            mine: hit.mine,
            ts: hit.ts,
            caption: hit.snippet,
            viewOnce: false
        )
    }

    /// Collects all eligible image/video carousel items from a timeline in chronological order, flattening gallery groups.
    public static func items(from timelineItems: [TimelineItem]) -> [CarouselItem] {
        var result: [CarouselItem] = []
        for timelineItem in timelineItems {
            switch timelineItem {
            case let .message(msg):
                if !msg.galleryItems.isEmpty {
                    guard !msg.viewOnce else { continue }
                    for galleryItem in msg.galleryItems where !galleryItem.showsMediaRemovedPlaceholder {
                        guard galleryItem.kind == .image || galleryItem.kind == .video else { continue }
                        let resolvedMediaPath = isLocalMediaStorePath(galleryItem.mediaPath) ? galleryItem.mediaPath : ""
                        let thumb = galleryItem.thumbnailPath ?? ""
                        let resolvedThumb = isLocalMediaStorePath(thumb) ? thumb : resolvedMediaPath
                        result.append(
                            CarouselItem(
                                eventID: galleryItem.id,
                                roomID: msg.roomID,
                                kind: galleryItem.kind,
                                mediaPath: resolvedMediaPath,
                                thumbnailPath: resolvedThumb,
                                fileName: galleryItem.fileName.isEmpty ? galleryItem.caption : galleryItem.fileName,
                                mimeType: galleryItem.mimeType,
                                width: galleryItem.width,
                                height: galleryItem.height,
                                blurhash: galleryItem.blurhash ?? "",
                                durationMS: galleryItem.durationMS,
                                isGIF: galleryItem.isGIF,
                                sender: msg.sender,
                                senderName: msg.senderName,
                                senderAvatarPath: msg.senderAvatarPath,
                                mine: msg.mine,
                                ts: msg.ts,
                                caption: galleryItem.caption != galleryItem.fileName ? galleryItem.caption : "",
                                viewOnce: false
                            )
                        )
                    }
                } else if let item = CarouselItem(message: msg) {
                    result.append(item)
                }
            default:
                break
            }
        }
        return result
    }

    /// Builds the deduplicated, chronological list of viewer items combining the open timeline, Chat Info's
    /// `sharedMedia` events, and paged `search.query` media hits.
    ///
    /// Strictly includes only non-view-once images and videos (never link previews, stickers, files, or deleted items).
    public static func viewerItems(
        timelineItems: [TimelineItem] = [],
        sharedMedia: [Event] = [],
        mediaHits: [MediaHit] = [],
        excludedViewOnceIDs: Set<String> = []
    ) -> [CarouselItem] {
        var excluded = excludedViewOnceIDs
        for item in timelineItems {
            guard case let .message(msg) = item else { continue }
            if msg.viewOnce || msg.kind == .deleted || msg.showsMediaRemovedPlaceholder {
                excluded.insert(msg.id)
                for galleryItem in msg.galleryItems {
                    excluded.insert(galleryItem.id)
                }
            }
        }

        var byID: [String: CarouselItem] = [:]
        func merge(_ incoming: CarouselItem) {
            guard !excluded.contains(incoming.eventID) else { return }
            guard let existing = byID[incoming.eventID] else {
                byID[incoming.eventID] = incoming
                return
            }
            let mergedMediaPath = !existing.mediaPath.isEmpty ? existing.mediaPath : incoming.mediaPath
            let mergedThumbPath = !existing.thumbnailPath.isEmpty
                ? existing.thumbnailPath
                : (!incoming.thumbnailPath.isEmpty ? incoming.thumbnailPath : mergedMediaPath)
            byID[incoming.eventID] = CarouselItem(
                eventID: existing.eventID,
                roomID: !existing.roomID.isEmpty ? existing.roomID : incoming.roomID,
                kind: existing.kind,
                mediaPath: mergedMediaPath,
                thumbnailPath: mergedThumbPath,
                fileName: !existing.fileName.isEmpty ? existing.fileName : incoming.fileName,
                mimeType: !existing.mimeType.isEmpty ? existing.mimeType : incoming.mimeType,
                width: existing.width ?? incoming.width,
                height: existing.height ?? incoming.height,
                blurhash: !existing.blurhash.isEmpty ? existing.blurhash : incoming.blurhash,
                durationMS: existing.durationMS ?? incoming.durationMS,
                isGIF: existing.isGIF || incoming.isGIF,
                sender: !existing.sender.isEmpty ? existing.sender : incoming.sender,
                senderName: !existing.senderName.isEmpty ? existing.senderName : incoming.senderName,
                senderAvatarPath: !existing.senderAvatarPath.isEmpty
                    ? existing.senderAvatarPath
                    : incoming.senderAvatarPath,
                mine: existing.mine || incoming.mine,
                ts: existing.ts > 0 ? existing.ts : incoming.ts,
                caption: !existing.caption.isEmpty ? existing.caption : incoming.caption,
                viewOnce: false
            )
        }

        for item in items(from: timelineItems) {
            merge(item)
        }
        for event in sharedMedia {
            if let item = CarouselItem(event: event) {
                merge(item)
            }
        }
        for hit in mediaHits {
            if let item = CarouselItem(hit: hit) {
                merge(item)
            }
        }

        return byID.values.sorted { lhs, rhs in
            if lhs.ts != rhs.ts {
                return lhs.ts < rhs.ts
            }
            return lhs.eventID < rhs.eventID
        }
    }
}

/// State and transform controls for the full-window attachment lightbox (`AttachmentCarousel.tsx`).
@MainActor
public final class AttachmentCarouselModel: ObservableObject {
    public static let minZoomScale: Double = 0.5
    public static let maxZoomScale: Double = 5.0
    public static let zoomStep: Double = 0.25

    @Published public private(set) var items: [CarouselItem] = []
    @Published public var currentIndex: Int = 0
    @Published public var zoomScale: Double = 1.0
    @Published public var rotationDegrees: Int = 0
    @Published public var isFlippedHorizontally: Bool = false
    @Published public var isFlippedVertically: Bool = false
    @Published public var isPlayingVideo: Bool = false
    @Published public var hasOlderItems: Bool = false
    @Published public var isLoadingOlderItems: Bool = false

    /// Called whenever the selected item changes or the carousel closes (`nil`).
    public var onSelectedEventChanged: ((String?) -> Void)?
    /// Called when navigating near the older edge while `hasOlderItems` is true.
    public var onLoadOlderItems: (() -> Void)?

    private weak var boundAppModel: AppModel?
    private weak var boundConversation: ConversationModel?
    private var roomSubscription: AnyCancellable?
    private var lightboxIDSubscription: AnyCancellable?
    private var mediaLoadEpoch: Int = 0
    private var mediaLoadTask: Task<Void, Never>?
    private var mediaNextCursor: String?
    private var mediaRoomID: String?
    private var usesThreadTimeline: Bool = false
    private var sharedMediaEvents: [Event] = []
    private var loadedMediaHits: [MediaHit] = []
    private var requestedEventID: String?
    private var didManuallyNavigateSinceOpen: Bool = false
    private var isApplyingSelectionUpdate: Bool = false

    public var isPresented: Bool {
        !items.isEmpty && items.indices.contains(currentIndex)
    }

    public var currentItem: CarouselItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public init() {}

    /// Connects the carousel to `appModel` and `conversation` so opening an attachment populates the chat's
    /// full image/video media list (matching Chat Info's Shared Media) and pages in older items on demand.
    public func bind(appModel: AppModel, conversation: ConversationModel) {
        boundAppModel = appModel
        if boundConversation !== conversation {
            boundConversation = conversation
            roomSubscription = conversation.$roomID
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self, weak conversation] _ in
                    if self?.isPresented == true {
                        conversation?.closeLightbox()
                    }
                }
            lightboxIDSubscription = conversation.$activeLightboxMessageID
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self, weak conversation] newID in
                    guard let self, let conversation,
                          let newID,
                          !self.isPresented,
                          !self.isApplyingSelectionUpdate
                    else { return }
                    Task { @MainActor [weak self, weak conversation] in
                        guard let self, let conversation,
                              conversation.activeLightboxMessageID == newID,
                              !self.isPresented
                        else { return }
                        self.openForRoom(selectedEventID: newID, roomID: conversation.roomID)
                    }
                }
        }
        if isPresented && mediaRoomID == nil {
            startRoomMediaSync(roomID: conversation.roomID ?? currentItem?.roomID, seedHits: [])
        }
    }

    /// Opens the carousel with `items`, selecting `selectedEventID`.
    ///
    /// View-once items, non-image/video kinds, and explicit remote URLs are excluded.
    /// If `selectedEventID` refers to a view-once item in `items`, the carousel refuses to open.
    public func open(items candidateItems: [CarouselItem], selectedEventID: String) {
        if candidateItems.first(where: { $0.eventID == selectedEventID })?.viewOnce == true {
            close()
            return
        }
        if let conv = boundConversation {
            if conv.isViewOnceEvent(selectedEventID) {
                close()
                return
            }
            if let msg = conv.message(selectedEventID, from: .chat) ?? conv.message(selectedEventID, from: .thread) {
                if msg.viewOnce || msg.kind == .deleted || msg.showsMediaRemovedPlaceholder {
                    close()
                    return
                }
                if msg.galleryItems.isEmpty && msg.kind != .image && msg.kind != .video {
                    close()
                    return
                }
            }
        }
        let eligible = candidateItems.filter {
            !$0.viewOnce
                && ($0.kind == .image || $0.kind == .video)
                && ($0.mediaPath.isEmpty || isLocalMediaStorePath($0.mediaPath))
        }
        guard !eligible.isEmpty else {
            close()
            return
        }

        mediaLoadEpoch += 1
        mediaLoadTask?.cancel()
        mediaLoadTask = nil
        mediaNextCursor = nil
        mediaRoomID = nil
        sharedMediaEvents = []
        loadedMediaHits = []
        hasOlderItems = false
        isLoadingOlderItems = false
        requestedEventID = selectedEventID
        didManuallyNavigateSinceOpen = false

        var startingItems = eligible
        var effectiveRoom = boundConversation?.roomID
            ?? eligible.first(where: { $0.eventID == selectedEventID })?.roomID
            ?? eligible.first?.roomID

        if let conv = boundConversation {
            if let convRoom = conv.roomID {
                effectiveRoom = convRoom
                usesThreadTimeline = !CarouselItem.items(from: conv.items).contains { $0.eventID == selectedEventID }
                    && CarouselItem.items(from: conv.thread.items).contains { $0.eventID == selectedEventID }
            } else {
                usesThreadTimeline = false
            }
            if let effectiveRoom,
               let info = conv.chatInfo,
               info.roomID == effectiveRoom || scopedRoomIDs(for: effectiveRoom).contains(info.roomID) {
                sharedMediaEvents = info.sharedMedia
            }
            if let effectiveRoom {
                let synced = CarouselItem.viewerItems(
                    timelineItems: activeTimelineItems(in: conv, for: effectiveRoom),
                    sharedMedia: sharedMediaEvents,
                    mediaHits: [],
                    excludedViewOnceIDs: excludedViewOnceIDs(in: conv)
                )
                if !synced.isEmpty && synced.contains(where: { $0.eventID == selectedEventID }) {
                    startingItems = synced
                }
            }
        }

        resetTransform()
        isPlayingVideo = false
        items = startingItems
        if let idx = startingItems.firstIndex(where: { $0.eventID == selectedEventID }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
        notifySelectedEventChanged(currentItem?.eventID)

        if boundAppModel != nil, let effectiveRoom, !effectiveRoom.isEmpty {
            startRoomMediaSync(roomID: effectiveRoom, seedHits: [])
        } else if currentIndex <= 3 {
            requestOlderItemsIfNeeded()
        }
    }

    /// Opens the viewer for `selectedEventID` in `roomID` (for Media Viewer or shared media tiles), seeding from
    /// any already-loaded hits and fetching the room's full image/video media history.
    public func openForRoom(selectedEventID: String, roomID targetRoomID: String?, seedHits: [MediaHit] = []) {
        if let appModel = boundAppModel,
           !AppLockGate.shared.canPerform(.other, lifecycle: appModel.lifecycle) {
            return
        }
        if boundConversation?.isViewOnceEvent(selectedEventID) == true
            || seedHits.first(where: { $0.eventID == selectedEventID })?.viewOnce == true {
            if let conv = boundConversation, onSelectedEventChanged == nil {
                onSelectedEventChanged = { [weak conv] id in conv?.activeLightboxMessageID = id }
            }
            close()
            return
        }
        if let conv = boundConversation,
           let msg = conv.message(selectedEventID, from: .chat) ?? conv.message(selectedEventID, from: .thread) {
            if msg.viewOnce || msg.kind == .deleted || msg.showsMediaRemovedPlaceholder
                || (msg.galleryItems.isEmpty && msg.kind != .image && msg.kind != .video) {
                if onSelectedEventChanged == nil {
                    onSelectedEventChanged = { [weak conv] id in conv?.activeLightboxMessageID = id }
                }
                close()
                return
            }
        }

        if let conv = boundConversation, onSelectedEventChanged == nil {
            onSelectedEventChanged = { [weak conv] id in
                conv?.activeLightboxMessageID = id
            }
        }

        mediaLoadEpoch += 1
        mediaLoadTask?.cancel()
        mediaLoadTask = nil
        mediaNextCursor = nil
        hasOlderItems = false
        isLoadingOlderItems = false
        requestedEventID = selectedEventID
        didManuallyNavigateSinceOpen = false

        let effectiveRoom = targetRoomID ?? boundConversation?.roomID ?? seedHits.first?.roomID
        mediaRoomID = effectiveRoom

        if let conv = boundConversation, let effectiveRoom, conv.roomID == effectiveRoom {
            usesThreadTimeline = !CarouselItem.items(from: conv.items).contains { $0.eventID == selectedEventID }
                && CarouselItem.items(from: conv.thread.items).contains { $0.eventID == selectedEventID }
        } else {
            usesThreadTimeline = false
        }

        if let conv = boundConversation,
           let effectiveRoom,
           let info = conv.chatInfo,
           info.roomID == effectiveRoom || scopedRoomIDs(for: effectiveRoom).contains(info.roomID) {
            sharedMediaEvents = info.sharedMedia
        } else {
            sharedMediaEvents = []
        }

        loadedMediaHits = seedHits.filter { hit in
            !hit.viewOnce && !(boundConversation?.isViewOnceEvent(hit.eventID) ?? false)
        }

        let timelineSource: [TimelineItem]
        if let conv = boundConversation, let effectiveRoom {
            timelineSource = activeTimelineItems(in: conv, for: effectiveRoom)
        } else {
            timelineSource = []
        }
        let excludedIDs = boundConversation.map(excludedViewOnceIDs(in:)) ?? []
        let initialItems = CarouselItem.viewerItems(
            timelineItems: timelineSource,
            sharedMedia: sharedMediaEvents,
            mediaHits: loadedMediaHits,
            excludedViewOnceIDs: excludedIDs
        )

        resetTransform()
        isPlayingVideo = false
        if !initialItems.isEmpty {
            items = initialItems
            if let idx = initialItems.firstIndex(where: { $0.eventID == selectedEventID }) {
                currentIndex = idx
            } else {
                currentIndex = max(0, initialItems.count - 1)
            }
            notifySelectedEventChanged(currentItem?.eventID)
        } else {
            items = []
            currentIndex = 0
        }

        startRoomMediaSync(roomID: effectiveRoom, seedHits: loadedMediaHits)
    }

    /// Replaces `items` with the merged chronological list while preserving the active item and transform state.
    public func mergeItems(_ candidateItems: [CarouselItem], hasOlder: Bool) {
        let activeID = (!didManuallyNavigateSinceOpen ? requestedEventID : nil) ?? currentItem?.eventID
        let eligible = candidateItems.filter {
            !$0.viewOnce
                && ($0.kind == .image || $0.kind == .video)
                && ($0.mediaPath.isEmpty || isLocalMediaStorePath($0.mediaPath))
        }
        guard !eligible.isEmpty else {
            hasOlderItems = false
            return
        }
        items = eligible
        hasOlderItems = hasOlder
        if let activeID, let idx = eligible.firstIndex(where: { $0.eventID == activeID }) {
            currentIndex = idx
        } else if !eligible.indices.contains(currentIndex) {
            currentIndex = max(0, eligible.count - 1)
        }
        notifySelectedEventChanged(currentItem?.eventID)
        if currentIndex <= 3 {
            requestOlderItemsIfNeeded()
        }
    }

    /// Requests the next older page of media if available and not already in flight.
    public func requestOlderItemsIfNeeded() {
        guard hasOlderItems, !isLoadingOlderItems else { return }
        onLoadOlderItems?()
    }

    /// Pages in older images and videos for the open viewer via `search.query(cursor:)`.
    public func loadOlderMedia() async {
        guard isPresented,
              !isLoadingOlderItems,
              let cursor = mediaNextCursor,
              !cursor.isEmpty,
              let effectiveRoom = mediaRoomID,
              let appModel = boundAppModel,
              AppLockGate.shared.canPerform(.other, lifecycle: appModel.lifecycle),
              let client = appModel.client
        else {
            return
        }
        let scopedRooms = scopedRoomIDs(for: effectiveRoom)
        guard !scopedRooms.isEmpty else { return }

        let epoch = mediaLoadEpoch
        isLoadingOlderItems = true
        defer {
            if epoch == mediaLoadEpoch {
                isLoadingOlderItems = false
            }
        }

        let response: LightboxMediaSearchResponse? = try? await client.call(
            "search.query",
            SearchParams(
                text: "",
                sections: [.media],
                filters: SearchFilters(roomIDs: scopedRooms, kinds: ["image", "video"]),
                cursor: cursor,
                limit: 50
            )
        )
        guard epoch == mediaLoadEpoch,
              AppLockGate.shared.canPerform(.other, lifecycle: appModel.lifecycle),
              client === appModel.client,
              isPresented,
              let page = response?.media
        else {
            return
        }

        var seen = Set(loadedMediaHits.map(\.eventID))
        for hit in page.hits where !hit.viewOnce && !(boundConversation?.isViewOnceEvent(hit.eventID) ?? false) {
            if seen.insert(hit.eventID).inserted {
                loadedMediaHits.append(hit)
            }
        }
        mediaNextCursor = page.nextCursor
        let hasOlder = (page.nextCursor?.isEmpty == false)
        let timelineSource = boundConversation.map { activeTimelineItems(in: $0, for: effectiveRoom) } ?? []
        let excludedIDs = boundConversation.map(excludedViewOnceIDs(in:)) ?? []
        let merged = CarouselItem.viewerItems(
            timelineItems: timelineSource,
            sharedMedia: sharedMediaEvents,
            mediaHits: loadedMediaHits,
            excludedViewOnceIDs: excludedIDs
        )
        mergeItems(merged, hasOlder: hasOlder)
    }

    /// Closes the lightbox and resets all transforms.
    public func close() {
        mediaLoadEpoch += 1
        mediaLoadTask?.cancel()
        mediaLoadTask = nil
        mediaNextCursor = nil
        mediaRoomID = nil
        usesThreadTimeline = false
        sharedMediaEvents = []
        loadedMediaHits = []
        requestedEventID = nil
        didManuallyNavigateSinceOpen = false
        items = []
        currentIndex = 0
        isPlayingVideo = false
        hasOlderItems = false
        isLoadingOlderItems = false
        onLoadOlderItems = nil
        resetTransform()
        notifySelectedEventChanged(nil)
    }

    /// Selects a specific index in `items` and resets image transforms.
    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        if index <= 3 {
            requestOlderItemsIfNeeded()
        }
        guard index != currentIndex else { return }
        didManuallyNavigateSinceOpen = true
        currentIndex = index
        resetTransform()
        isPlayingVideo = false
        notifySelectedEventChanged(currentItem?.eventID)
    }

    /// Moves to the next attachment in `items` if available.
    public func next() {
        guard currentIndex + 1 < items.count else { return }
        didManuallyNavigateSinceOpen = true
        currentIndex += 1
        resetTransform()
        isPlayingVideo = false
        notifySelectedEventChanged(currentItem?.eventID)
    }

    /// Moves to the previous attachment in `items` if available.
    public func previous() {
        guard currentIndex > 0 else {
            requestOlderItemsIfNeeded()
            return
        }
        didManuallyNavigateSinceOpen = true
        currentIndex -= 1
        resetTransform()
        isPlayingVideo = false
        notifySelectedEventChanged(currentItem?.eventID)
        if currentIndex <= 3 {
            requestOlderItemsIfNeeded()
        }
    }

    /// Steps zoom scale up by `0.25` up to `5.0`.
    public func zoomIn() {
        zoomScale = min(Self.maxZoomScale, (zoomScale + Self.zoomStep))
    }

    /// Steps zoom scale down by `0.25` down to `0.5`.
    public func zoomOut() {
        zoomScale = max(Self.minZoomScale, (zoomScale - Self.zoomStep))
    }

    /// Resets zoom to 100%, rotation to 0°, and clears horizontal/vertical flip.
    public func resetTransform() {
        zoomScale = 1.0
        rotationDegrees = 0
        isFlippedHorizontally = false
        isFlippedVertically = false
    }

    /// Rotates 90° clockwise (`0` -> `90` -> `180` -> `270` -> `0`).
    public func rotateClockwise() {
        rotationDegrees = (rotationDegrees + 90) % 360
    }

    /// Toggles horizontal mirror flip.
    public func flipHorizontal() {
        isFlippedHorizontally.toggle()
    }

    /// Toggles vertical mirror flip.
    public func flipVertical() {
        isFlippedVertically.toggle()
    }

    /// Toggles playback when the active item is a video.
    public func toggleVideoPlayback() {
        guard currentItem?.kind == .video else { return }
        isPlayingVideo.toggle()
    }

    // MARK: - Room Media Sync Helpers

    private struct LightboxMediaSearchResponse: Decodable {
        struct Page: Decodable {
            let hits: [MediaHit]
            let nextCursor: String?

            enum CodingKeys: String, CodingKey {
                case hits
                case nextCursor = "next_cursor"
            }
        }

        let media: Page?
    }

    private func notifySelectedEventChanged(_ eventID: String?) {
        isApplyingSelectionUpdate = true
        defer { isApplyingSelectionUpdate = false }
        onSelectedEventChanged?(eventID)
    }

    private func scopedRoomIDs(for targetRoom: String) -> [String] {
        guard let appModel = boundAppModel else {
            return targetRoom.hasPrefix("merge:") ? [] : [targetRoom]
        }
        return appModel.scopeRoomIDs(for: targetRoom).filter { !$0.hasPrefix("merge:") }
    }

    private func activeTimelineItems(in conversation: ConversationModel, for targetRoom: String) -> [TimelineItem] {
        guard targetRoom == conversation.roomID else { return [] }
        return usesThreadTimeline ? conversation.thread.items : conversation.items
    }

    private func excludedViewOnceIDs(in conversation: ConversationModel) -> Set<String> {
        var excluded = Set<String>()
        for item in conversation.items + conversation.thread.items {
            guard case let .message(msg) = item else { continue }
            if msg.viewOnce || msg.kind == .deleted || msg.showsMediaRemovedPlaceholder {
                excluded.insert(msg.id)
                for galleryItem in msg.galleryItems {
                    excluded.insert(galleryItem.id)
                }
            }
        }
        return excluded
    }

    private func startRoomMediaSync(roomID targetRoomID: String?, seedHits: [MediaHit]) {
        mediaRoomID = targetRoomID
        if !seedHits.isEmpty {
            var seen = Set(loadedMediaHits.map(\.eventID))
            for hit in seedHits where !hit.viewOnce && !(boundConversation?.isViewOnceEvent(hit.eventID) ?? false) {
                if seen.insert(hit.eventID).inserted {
                    loadedMediaHits.append(hit)
                }
            }
        }
        onLoadOlderItems = { [weak self] in
            Task { await self?.loadOlderMedia() }
        }

        guard let appModel = boundAppModel,
              let client = appModel.client,
              let effectiveRoom = targetRoomID,
              !effectiveRoom.isEmpty
        else {
            return
        }
        let scopedRooms = scopedRoomIDs(for: effectiveRoom)
        guard !scopedRooms.isEmpty else { return }

        let epoch = mediaLoadEpoch
        let shouldFetchRoomInfo = sharedMediaEvents.isEmpty && scopedRooms.count == 1
        let singleRoom = scopedRooms[0]

        mediaLoadTask = Task { [weak self] in
            async let roomInfoCall: RoomInfoResult? = shouldFetchRoomInfo
                ? (try? client.call("room.info", RoomInfoParams(roomID: singleRoom)))
                : nil
            async let mediaSearchCall: LightboxMediaSearchResponse? = try? client.call(
                "search.query",
                SearchParams(
                    text: "",
                    sections: [.media],
                    filters: SearchFilters(roomIDs: scopedRooms, kinds: ["image", "video"]),
                    cursor: nil,
                    limit: 50
                )
            )
            let fetchedInfo = await roomInfoCall
            let mediaResponse = await mediaSearchCall
            guard let self,
                  !Task.isCancelled,
                  epoch == self.mediaLoadEpoch,
                  AppLockGate.shared.canPerform(.other, lifecycle: appModel.lifecycle),
                  client === appModel.client
            else {
                return
            }

            if let fetchedInfo {
                self.sharedMediaEvents = fetchedInfo.sharedMedia
            }
            if let page = mediaResponse?.media {
                var seen = Set(self.loadedMediaHits.map(\.eventID))
                for hit in page.hits where !hit.viewOnce && !(self.boundConversation?.isViewOnceEvent(hit.eventID) ?? false) {
                    if seen.insert(hit.eventID).inserted {
                        self.loadedMediaHits.append(hit)
                    }
                }
                self.mediaNextCursor = page.nextCursor
            }
            let hasOlder = (self.mediaNextCursor?.isEmpty == false)
            let timelineSource = self.boundConversation.map { self.activeTimelineItems(in: $0, for: effectiveRoom) } ?? []
            let excludedIDs = self.boundConversation.map(self.excludedViewOnceIDs(in:)) ?? []
            let merged = CarouselItem.viewerItems(
                timelineItems: timelineSource,
                sharedMedia: self.sharedMediaEvents,
                mediaHits: self.loadedMediaHits,
                excludedViewOnceIDs: excludedIDs
            )
            if self.isPresented {
                self.mergeItems(merged, hasOlder: hasOlder)
            } else if !merged.isEmpty {
                self.items = merged
                self.hasOlderItems = hasOlder
                if let targetID = self.requestedEventID,
                   let idx = merged.firstIndex(where: { $0.eventID == targetID }) {
                    self.currentIndex = idx
                } else {
                    self.currentIndex = max(0, merged.count - 1)
                }
                self.notifySelectedEventChanged(self.currentItem?.eventID)
                if self.currentIndex <= 3 {
                    self.requestOlderItemsIfNeeded()
                }
            } else {
                self.notifySelectedEventChanged(nil)
            }
        }
    }
}
