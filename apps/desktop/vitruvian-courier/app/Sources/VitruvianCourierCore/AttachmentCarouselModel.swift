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

/// One image, video or sticker item shown in `AttachmentCarouselOverlay`.
///
/// Only non-view-once images, videos and stickers belong in the viewer (the same set Chat Info's **Shared Media**
/// counts, excluding link previews, files, voice notes, and removed media). Local paths are sanitized through
/// `isLocalMediaStorePath`; an item whose local file is not yet downloaded keeps `mediaPath == ""` so the viewer
/// count matches Chat Info and its thumbnail renders a neutral placeholder instead of blank.
public struct CarouselItem: Identifiable, Equatable, Sendable {
    /// The kinds the viewer shows, by the names the engine's search uses. This is the one definition on the Swift
    /// side; the engine's `store.SharedMediaKinds` (Chat Info's Shared Media) lists the same kinds, and a test on each
    /// side pins them.
    public static let viewableKindNames: [String] = ["image", "video", "sticker"]

    /// Whether a message of `kind` is one the viewer shows.
    public static func isViewableKind(_ kind: MessageKind) -> Bool {
        switch kind {
        case .image: viewableKindNames.contains("image")
        case .video: viewableKindNames.contains("video")
        case .sticker: viewableKindNames.contains("sticker")
        default: false
        }
    }

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
    public let reactions: [ReactionChip]

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
        viewOnce: Bool = false,
        reactions: [ReactionChip] = []
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
        self.reactions = reactions
    }

    /// Creates a `CarouselItem` from a `TimelineMessage` if it is a non-view-once image, video or sticker.
    public init?(message: TimelineMessage) {
        guard !message.viewOnce,
              !message.showsMediaRemovedPlaceholder,
              Self.isViewableKind(message.kind)
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
            viewOnce: false,
            reactions: message.reactions
        )
    }

    /// Creates a `CarouselItem` from a raw `Event` (such as `RoomInfoResult.sharedMedia`) if it is a non-view-once
    /// image, video or sticker (`m.image` / `m.video` / `m.sticker`). Strictly excludes link previews (`m.text`),
    /// files, and audio.
    public init?(event: Event) {
        guard event.type == "m.room.message" || event.type == "m.sticker",
              event.viewOnce != true,
              case let .object(dict) = event.content,
              dict["com.courier.media_removed"] != .bool(true)
        else {
            return nil
        }
        // A sticker is its own event type; every other media event names its kind in `msgtype`.
        guard let msgtype = event.type == "m.sticker" ? "m.sticker" : dict["msgtype"]?.stringValue else {
            return nil
        }
        let kind: MessageKind
        switch msgtype {
        case "m.image":
            kind = .image
        case "m.video":
            kind = .video
        case "m.sticker":
            kind = .sticker
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

    /// Creates a `CarouselItem` from a `MediaHit` if it is a non-view-once image, video or sticker.
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
        case .sticker:
            messageKind = .sticker
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
                        guard isViewableKind(galleryItem.kind) else { continue }
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
                                viewOnce: false,
                                reactions: galleryItem.reactions
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

    /// This item with `reactions` as its reactions.
    public func withReactions(_ reactions: [ReactionChip]) -> CarouselItem {
        CarouselItem(
            eventID: eventID,
            roomID: roomID,
            kind: kind,
            mediaPath: mediaPath,
            thumbnailPath: thumbnailPath,
            fileName: fileName,
            mimeType: mimeType,
            width: width,
            height: height,
            blurhash: blurhash,
            durationMS: durationMS,
            isGIF: isGIF,
            sender: sender,
            senderName: senderName,
            senderAvatarPath: senderAvatarPath,
            mine: mine,
            ts: ts,
            caption: caption,
            viewOnce: viewOnce,
            reactions: reactions
        )
    }

    /// `items` with each one's reactions taken from `timelineItems`. An item whose event the timeline doesn't have
    /// (older media paged in from the engine) keeps the reactions it has.
    public static func applyingReactions(from timelineItems: [TimelineItem], to items: [CarouselItem]) -> [CarouselItem] {
        let byEvent = reactionsByEventID(from: timelineItems)
        return items.map { item in
            guard let reactions = byEvent[item.eventID], reactions != item.reactions else { return item }
            return item.withReactions(reactions)
        }
    }

    /// Collects reactions keyed by event ID for single media messages and gallery tiles from `timelineItems`.
    public static func reactionsByEventID(from timelineItems: [TimelineItem]) -> [String: [ReactionChip]] {
        var result: [String: [ReactionChip]] = [:]
        for timelineItem in timelineItems {
            guard case let .message(msg) = timelineItem else { continue }
            if !msg.galleryItems.isEmpty {
                for galleryItem in msg.galleryItems {
                    result[galleryItem.id] = galleryItem.reactions
                }
            } else {
                result[msg.id] = msg.reactions
            }
        }
        return result
    }

    /// Decides which items the viewer shows: the deduplicated, chronological union of the open timeline, Chat Info's
    /// `sharedMedia` events and the `search.query` media hits.
    ///
    /// Only images, videos and stickers that are not view-once, deleted or removed belong (never link previews,
    /// files or voice notes), and one whose file is not downloaded yet stays in, with an empty `mediaPath`.
    public static func viewerItems(
        timelineItems: [TimelineItem] = [],
        sharedMedia: [Event] = [],
        mediaHits: [MediaHit] = []
    ) -> [CarouselItem] {
        var excluded = Set<String>()
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
                viewOnce: false,
                reactions: !existing.reactions.isEmpty ? existing.reactions : incoming.reactions
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

        let sorted = byID.values.sorted { lhs, rhs in
            if lhs.ts != rhs.ts {
                return lhs.ts < rhs.ts
            }
            return lhs.eventID < rhs.eventID
        }
        // Media that came in as a search or paging hit carries no reactions of its own: take them from the timeline.
        return applyingReactions(from: timelineItems, to: sorted)
    }
}

/// State and transform controls for the full-window attachment lightbox (`AttachmentCarousel.tsx`).
///
/// Opening it shows the chat's whole list of images, videos and stickers (what Chat Info calls Shared Media), not only what
/// the timeline has loaded: the rest is paged in from the engine as you move toward the oldest end.
@MainActor
public final class AttachmentCarouselModel: ObservableObject {
    public static let minZoomScale: Double = 0.5
    public static let maxZoomScale: Double = 5.0
    public static let zoomStep: Double = 0.25
    /// Older items are requested once the selection is this close to the oldest loaded item.
    private static let pagingMargin = 3

    @Published public private(set) var items: [CarouselItem] = []
    @Published public var currentIndex: Int = 0
    @Published public var zoomScale: Double = 1.0
    @Published public var rotationDegrees: Int = 0
    @Published public var isFlippedHorizontally: Bool = false
    @Published public var isFlippedVertically: Bool = false
    @Published public var isPlayingVideo: Bool = false
    @Published public private(set) var hasOlderItems: Bool = false
    @Published public private(set) var isLoadingOlderItems: Bool = false

    /// Called whenever the selected item changes or the carousel closes (`nil`).
    public var onSelectedEventChanged: ((String?) -> Void)?

    private weak var appModel: AppModel?
    private weak var conversation: ConversationModel?
    /// Goes up on every open and close, so a page that arrives for an earlier open is dropped.
    private var epoch = 0
    private var pager: MediaViewerModel?
    private var pagingTask: Task<Void, Never>?
    private var sessionRoomID: String?
    private var seedHits: [MediaHit] = []
    private var pagedHits: [MediaHit] = []
    private var requestedEventID: String?
    private var userHasNavigated = false
    private var timelineSubscriptions: [AnyCancellable] = []

    public var isPresented: Bool {
        !items.isEmpty && items.indices.contains(currentIndex)
    }

    public var currentItem: CarouselItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    /// "3 / 12": where the selection is among the loaded items. A single item reads "1 / 1".
    public var positionLabel: String {
        "\(currentIndex + 1) / \(items.count)"
    }

    /// Whether ← has an item to go to.
    public var canGoPrevious: Bool { currentIndex > 0 }

    /// Whether → has an item to go to.
    public var canGoNext: Bool { currentIndex + 1 < items.count }

    public init() {}

    /// Connects the carousel to the engine (to page in the chat's older media) and to the conversation (to keep its
    /// selected-message ID in step and to know what is view-once).
    public func bind(appModel: AppModel, conversation: ConversationModel) {
        self.appModel = appModel
        self.conversation = conversation
        onSelectedEventChanged = { [weak conversation] id in conversation?.activeLightboxMessageID = id }
        // The chips follow the timeline while the viewer is open: my own reaction from the React button and ones that
        // arrive from others. `@Published` hands over the new value before the property changes, so use that.
        timelineSubscriptions = [
            conversation.$items.dropFirst().sink { [weak self, weak conversation] chatItems in
                guard let conversation else { return }
                self?.syncReactions(from: chatItems + conversation.thread.items)
            },
            conversation.thread.$items.dropFirst().sink { [weak self, weak conversation] threadItems in
                guard let conversation else { return }
                self?.syncReactions(from: conversation.items + threadItems)
            },
        ]
    }

    private func syncReactions(from timelineItems: [TimelineItem]) {
        guard !items.isEmpty else { return }
        let updated = CarouselItem.applyingReactions(from: timelineItems, to: items)
        if updated != items {
            items = updated
        }
    }

    /// Opens the carousel with `items`, selecting `selectedEventID`, then widens it to the chat's full list of
    /// images, videos and stickers.
    ///
    /// View-once items, anything that is not an image, video or sticker, and explicit remote URLs are excluded. If
    /// `selectedEventID` refers to a view-once item, the carousel refuses to open.
    public func open(items candidateItems: [CarouselItem], selectedEventID: String) {
        present(candidates: candidateItems, selectedEventID: selectedEventID, roomID: nil, seedHits: [])
    }

    /// Opens the carousel on `selectedEventID` in `roomID` from outside the timeline (the Media Viewer window),
    /// seeded with the `seedHits` it already loaded.
    public func openForRoom(selectedEventID: String, roomID: String?, seedHits: [MediaHit] = []) {
        present(
            candidates: seedHits.compactMap(CarouselItem.init(hit:)),
            selectedEventID: selectedEventID,
            roomID: roomID,
            seedHits: seedHits
        )
    }

    private static func isViewable(_ item: CarouselItem) -> Bool {
        !item.viewOnce
            && CarouselItem.isViewableKind(item.kind)
            && (item.mediaPath.isEmpty || isLocalMediaStorePath(item.mediaPath))
    }

    private func present(candidates: [CarouselItem], selectedEventID: String, roomID: String?, seedHits: [MediaHit]) {
        if candidates.first(where: { $0.eventID == selectedEventID })?.viewOnce == true
            || seedHits.first(where: { $0.eventID == selectedEventID })?.viewOnce == true
            || conversation?.isViewOnceEvent(selectedEventID) == true {
            close()
            return
        }
        let eligible = candidates.filter(Self.isViewable)

        endSession()
        sessionRoomID = roomID ?? conversation?.roomID ?? eligible.first?.roomID
        self.seedHits = seedHits.filter { !$0.viewOnce && conversation?.isViewOnceEvent($0.eventID) != true }
        requestedEventID = selectedEventID

        let known = mergedItems()
        let start = known.contains { $0.eventID == selectedEventID } ? known : eligible
        resetTransform()
        isPlayingVideo = false
        items = start
        currentIndex = start.firstIndex { $0.eventID == selectedEventID } ?? 0
        if isPresented {
            onSelectedEventChanged?(currentItem?.eventID)
        }
        startPaging()
    }

    /// Closes the lightbox and resets all transforms.
    public func close() {
        endSession()
        items = []
        currentIndex = 0
        isPlayingVideo = false
        resetTransform()
        onSelectedEventChanged?(nil)
    }

    /// Forgets everything about the open that is ending, and drops any page still on its way for it.
    private func endSession() {
        epoch += 1
        pagingTask?.cancel()
        pagingTask = nil
        pager = nil
        sessionRoomID = nil
        seedHits = []
        pagedHits = []
        requestedEventID = nil
        userHasNavigated = false
        hasOlderItems = false
        isLoadingOlderItems = false
    }

    /// Selects a specific index in `items` and resets image transforms.
    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        if index <= Self.pagingMargin {
            requestOlderItemsIfNeeded()
        }
        guard index != currentIndex else { return }
        move(to: index)
    }

    /// Moves to the next attachment in `items` if available.
    public func next() {
        guard currentIndex + 1 < items.count else { return }
        move(to: currentIndex + 1)
    }

    /// Moves to the previous attachment in `items` if available.
    public func previous() {
        guard currentIndex > 0 else {
            requestOlderItemsIfNeeded()
            return
        }
        move(to: currentIndex - 1)
        if currentIndex <= Self.pagingMargin {
            requestOlderItemsIfNeeded()
        }
    }

    private func move(to index: Int) {
        userHasNavigated = true
        currentIndex = index
        resetTransform()
        isPlayingVideo = false
        onSelectedEventChanged?(currentItem?.eventID)
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

    // MARK: - The chat's full media list

    /// Asks for the next page of older media, unless there is none or one is already on its way.
    public func requestOlderItemsIfNeeded() {
        guard hasOlderItems, !isLoadingOlderItems else { return }
        Task { await loadOlderMedia() }
    }

    /// Pages in the next older images, videos and stickers for the open viewer.
    public func loadOlderMedia() async {
        guard isPresented, !isLoadingOlderItems, let pager, pager.hasMore else { return }
        let epoch = epoch
        isLoadingOlderItems = true
        defer {
            if epoch == self.epoch {
                isLoadingOlderItems = false
            }
        }
        await pager.loadNextPage()
        absorbPage(from: pager, epoch: epoch)
    }

    private func startPaging() {
        guard let appModel, let room = sessionRoomID, !room.isEmpty, !scopedRoomIDs(for: room).isEmpty else { return }
        let pager = MediaViewerModel(appModel: appModel, roomID: room, conversation: conversation)
        self.pager = pager
        let epoch = epoch
        isLoadingOlderItems = true
        pagingTask = Task { [weak self] in
            await pager.refresh()
            guard let self, epoch == self.epoch else { return }
            self.isLoadingOlderItems = false
            self.absorbPage(from: pager, epoch: epoch)
        }
    }

    /// Folds what `pager` has loaded so far into the list, keeping the same item selected.
    private func absorbPage(from pager: MediaViewerModel, epoch: Int) {
        guard epoch == self.epoch, !Task.isCancelled else { return }
        pagedHits = pager.items
        hasOlderItems = pager.hasMore
        let merged = mergedItems()
        guard !merged.isEmpty else { return }
        if !isPresented {
            // Opened from outside the timeline with nothing to show yet: open once the item is there.
            guard let requestedEventID, merged.contains(where: { $0.eventID == requestedEventID }) else { return }
        }
        let activeID = (userHasNavigated ? nil : requestedEventID) ?? currentItem?.eventID
        let previousID = currentItem?.eventID
        items = merged
        currentIndex = activeID.flatMap { id in merged.firstIndex { $0.eventID == id } }
            ?? min(currentIndex, merged.count - 1)
        if currentItem?.eventID != previousID {
            onSelectedEventChanged?(currentItem?.eventID)
        }
        if currentIndex <= Self.pagingMargin {
            requestOlderItemsIfNeeded()
        }
    }

    /// Timeline, Chat Info's Shared Media and every page loaded so far, as one deduplicated list.
    private func mergedItems() -> [CarouselItem] {
        var timeline: [TimelineItem] = []
        var sharedMedia: [Event] = []
        if let conversation, let room = sessionRoomID {
            if room == conversation.roomID {
                timeline = conversation.items + conversation.thread.items
            }
            if let info = conversation.chatInfo, scopedRoomIDs(for: room).contains(info.roomID) {
                sharedMedia = info.sharedMedia
            }
        }
        return CarouselItem.viewerItems(timelineItems: timeline, sharedMedia: sharedMedia, mediaHits: seedHits + pagedHits)
    }

    private func scopedRoomIDs(for room: String) -> [String] {
        guard let appModel else { return room.hasPrefix("merge:") ? [] : [room] }
        return appModel.scopeRoomIDs(for: room).filter { !$0.hasPrefix("merge:") }
    }
}
