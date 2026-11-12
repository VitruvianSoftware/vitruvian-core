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

/// One image, video, or sticker item shown in `AttachmentCarouselOverlay`.
///
/// Only local media store files (`isLocalMediaStorePath`) that are not view-once (`!viewOnce`)
/// may appear in the attachment carousel.
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

    /// Creates a `CarouselItem` from a `TimelineMessage` if it is a non-view-once local-store image, video, or sticker.
    public init?(message: TimelineMessage) {
        guard !message.viewOnce,
              message.kind != .deleted,
              message.kind == .image || message.kind == .video || message.kind == .sticker
        else {
            return nil
        }
        let thumb = message.thumbnailPath ?? ""
        let resolvedMediaPath = !message.mediaPath.isEmpty ? message.mediaPath : thumb
        guard isLocalMediaStorePath(resolvedMediaPath) else { return nil }
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

    /// Creates a `CarouselItem` from a `MediaHit` if it is a non-view-once local-store image, video, or sticker.
    public init?(hit: MediaHit) {
        guard !hit.viewOnce,
              isLocalMediaStorePath(hit.mediaPath)
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
        self.init(
            eventID: hit.eventID,
            roomID: hit.roomID,
            kind: messageKind,
            mediaPath: hit.mediaPath,
            thumbnailPath: hit.mediaPath,
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

    /// Collects all eligible carousel items from a timeline in chronological order, flattening gallery groups.
    public static func items(from timelineItems: [TimelineItem]) -> [CarouselItem] {
        var result: [CarouselItem] = []
        for timelineItem in timelineItems {
            switch timelineItem {
            case let .message(msg):
                if let item = CarouselItem(message: msg) {
                    result.append(item)
                } else if !msg.galleryItems.isEmpty && !msg.viewOnce {
                    for galleryItem in msg.galleryItems {
                        if isLocalMediaStorePath(galleryItem.mediaPath) {
                            let thumb = galleryItem.thumbnailPath ?? ""
                            result.append(
                                CarouselItem(
                                    eventID: galleryItem.id,
                                    roomID: msg.roomID,
                                    kind: galleryItem.kind,
                                    mediaPath: galleryItem.mediaPath,
                                    thumbnailPath: isLocalMediaStorePath(thumb)
                                        ? thumb
                                        : galleryItem.mediaPath,
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
                    }
                }
            default:
                break
            }
        }
        return result
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

    /// Called whenever the selected item changes or the carousel closes (`nil`).
    public var onSelectedEventChanged: ((String?) -> Void)?

    public var isPresented: Bool {
        !items.isEmpty && items.indices.contains(currentIndex)
    }

    public var currentItem: CarouselItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public init() {}

    /// Opens the carousel with `items`, selecting `selectedEventID`.
    ///
    /// View-once items and non-local-store items are always excluded. If `selectedEventID` refers to a view-once
    /// item in `items`, the carousel refuses to open.
    public func open(items candidateItems: [CarouselItem], selectedEventID: String) {
        if candidateItems.first(where: { $0.eventID == selectedEventID })?.viewOnce == true {
            close()
            return
        }
        let eligible = candidateItems.filter { !$0.viewOnce && isLocalMediaStorePath($0.mediaPath) }
        guard !eligible.isEmpty else {
            close()
            return
        }
        resetTransform()
        isPlayingVideo = false
        items = eligible
        if let idx = eligible.firstIndex(where: { $0.eventID == selectedEventID }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
        onSelectedEventChanged?(currentItem?.eventID)
    }

    /// Closes the lightbox and resets all transforms.
    public func close() {
        items = []
        currentIndex = 0
        isPlayingVideo = false
        resetTransform()
        onSelectedEventChanged?(nil)
    }

    /// Selects a specific index in `items` and resets image transforms.
    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        guard index != currentIndex else { return }
        currentIndex = index
        resetTransform()
        isPlayingVideo = false
        onSelectedEventChanged?(currentItem?.eventID)
    }

    /// Moves to the next attachment in `items` if available.
    public func next() {
        guard currentIndex + 1 < items.count else { return }
        currentIndex += 1
        resetTransform()
        isPlayingVideo = false
        onSelectedEventChanged?(currentItem?.eventID)
    }

    /// Moves to the previous attachment in `items` if available.
    public func previous() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
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
}
