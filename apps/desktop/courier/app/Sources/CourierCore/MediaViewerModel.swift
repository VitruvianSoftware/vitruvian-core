// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// One media, link, or document item in `MediaViewerModel`.
public struct MediaHit: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: String { eventID }
    public var eventID: String
    public var roomID: String
    public var roomName: String
    public var network: String
    public var isDirect: Bool
    public var place: ChatPlace
    public var sender: String
    public var senderName: String
    public var mine: Bool
    public var ts: Int64
    public var seq: Int64
    public var kind: MessageHitKind
    public var snippet: String
    public var ranges: [TextRange]
    public var mediaPath: String
    public var partial: Bool
    public var viewOnce: Bool

    public init(
        eventID: String,
        roomID: String,
        roomName: String = "",
        network: String = "whatsapp",
        isDirect: Bool = true,
        place: ChatPlace = .inbox,
        sender: String,
        senderName: String,
        mine: Bool,
        ts: Int64,
        seq: Int64,
        kind: MessageHitKind = .image,
        snippet: String = "",
        ranges: [TextRange] = [],
        mediaPath: String = "",
        partial: Bool = false,
        viewOnce: Bool = false
    ) {
        self.eventID = eventID
        self.roomID = roomID
        self.roomName = roomName
        self.network = network
        self.isDirect = isDirect
        self.place = place
        self.sender = sender
        self.senderName = senderName
        self.mine = mine
        self.ts = ts
        self.seq = seq
        self.kind = kind
        self.snippet = snippet
        self.ranges = ranges
        self.mediaPath = mediaPath
        self.partial = partial
        self.viewOnce = viewOnce
    }

    public init(messageHit: MessageHit, viewOnce: Bool = false) {
        self.init(
            eventID: messageHit.eventID,
            roomID: messageHit.roomID,
            roomName: messageHit.roomName,
            network: messageHit.network,
            isDirect: messageHit.isDirect,
            place: messageHit.place,
            sender: messageHit.sender,
            senderName: messageHit.senderName,
            mine: messageHit.mine,
            ts: messageHit.ts,
            seq: messageHit.seq,
            kind: messageHit.kind,
            snippet: messageHit.snippet,
            ranges: messageHit.ranges,
            mediaPath: messageHit.mediaPath,
            partial: messageHit.partial,
            viewOnce: messageHit.viewOnce ?? viewOnce
        )
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case roomID = "room_id"
        case roomName = "room_name"
        case network
        case isDirect = "is_direct"
        case place
        case sender
        case senderName = "sender_name"
        case mine
        case ts
        case seq
        case kind
        case snippet
        case ranges
        case mediaPath = "media_path"
        case partial
        case viewOnce = "view_once"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decode(String.self, forKey: .eventID)
        roomID = try container.decode(String.self, forKey: .roomID)
        roomName = try container.decodeIfPresent(String.self, forKey: .roomName) ?? ""
        network = try container.decodeIfPresent(String.self, forKey: .network) ?? ""
        isDirect = try container.decodeIfPresent(Bool.self, forKey: .isDirect) ?? false
        place = try container.decodeIfPresent(ChatPlace.self, forKey: .place) ?? .inbox
        sender = try container.decodeIfPresent(String.self, forKey: .sender) ?? ""
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        mine = try container.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        ts = try container.decodeIfPresent(Int64.self, forKey: .ts) ?? 0
        seq = try container.decodeIfPresent(Int64.self, forKey: .seq) ?? 0
        kind = try container.decodeIfPresent(MessageHitKind.self, forKey: .kind) ?? .text
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet) ?? ""
        ranges = try container.decodeIfPresent([TextRange].self, forKey: .ranges) ?? []
        mediaPath = try container.decodeIfPresent(String.self, forKey: .mediaPath) ?? ""
        partial = try container.decodeIfPresent(Bool.self, forKey: .partial) ?? false
        viewOnce = try container.decodeIfPresent(Bool.self, forKey: .viewOnce) ?? false
    }

    /// Best display filename for a media or document hit.
    public var fileName: String {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, extractedURL == nil {
            return trimmed
        }
        let last = (mediaPath as NSString).lastPathComponent
        return last.isEmpty ? eventID : last
    }

    /// First HTTP(S) URL extracted from `snippet`, trimmed of trailing punctuation.
    public var extractedURL: String? {
        for token in snippet.split(whereSeparator: \.isWhitespace) {
            let str = String(token)
            let range = str.range(of: "https://", options: [.caseInsensitive])
                ?? str.range(of: "http://", options: [.caseInsensitive])
            guard let range else { continue }
            var candidate = String(str[range.lowerBound...])
            while let last = candidate.last, ".,;:!?)>]'\"".contains(last) {
                candidate.removeLast()
            }
            if candidate.lowercased() != "http://" && candidate.lowercased() != "https://" {
                return candidate
            }
        }
        return nil
    }

    /// Hostname of `extractedURL`, when valid.
    public var extractedHost: String? {
        guard let raw = extractedURL, let url = URL(string: raw), let host = url.host, !host.isEmpty else {
            return nil
        }
        return host
    }
}

/// Target passed to `openWindow(id: WindowID.mediaViewer, value:)` so `Chat Info`'s **See All** buttons
/// and the command bar can open `MediaViewerWindow` on a specific chat and tab.
public struct MediaViewerTarget: Codable, Hashable, Sendable {
    public var roomID: String?
    public var initialTab: String

    public init(roomID: String? = nil, tab: MediaViewerModel.Tab = .media) {
        self.roomID = roomID
        self.initialTab = tab.rawValue
    }

    public var resolvedTab: MediaViewerModel.Tab {
        MediaViewerModel.Tab(rawValue: initialTab) ?? .media
    }
}

/// Paged Media / Links / Docs browser model (`MediaViewerBrowserWindow.tsx`).
///
/// Queries the local store via `search.query` one page at a time (`limit: 50` with `cursor`),
/// expands merged chats through `AppModel.scopeRoomIDs(for:)` so `"merge:…"` never crosses the RPC boundary,
/// and filters out view-once media.
@MainActor
public final class MediaViewerModel: ObservableObject {
    public enum Tab: String, CaseIterable, Sendable {
        case media = "Media"
        case links = "Links"
        case docs = "Docs"
    }

    public enum SentByFilter: String, CaseIterable, Sendable {
        case all = "All"
        case you = "You"
        case others = "Others"
    }

    public enum SortOrder: String, CaseIterable, Sendable {
        case newest = "Newest"
        case oldest = "Oldest"
    }

    @Published public var tab: Tab = .media
    @Published public var sentBy: SentByFilter = .all
    @Published public var sortOrder: SortOrder = .newest {
        didSet {
            if sortOrder != oldValue {
                items = Self.sorted(rawItems, by: sortOrder)
            }
        }
    }
    @Published public var query: String = ""
    @Published public var roomID: String?
    @Published public private(set) var items: [MediaHit] = []
    @Published public var selectedEventIDs: Set<String> = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var hasMore: Bool = false

    public let appModel: AppModel
    public weak var conversation: ConversationModel?
    public var knownViewOnceEventIDs: Set<String>
    public var pageLimit: Int = 50

    private var rawItems: [MediaHit] = []
    private var nextCursor: String?

    public init(
        appModel: AppModel,
        roomID: String? = nil,
        conversation: ConversationModel? = nil,
        knownViewOnceEventIDs: Set<String> = [],
        initialItems: [MediaHit] = []
    ) {
        self.appModel = appModel
        self.roomID = roomID
        self.conversation = conversation
        self.knownViewOnceEventIDs = knownViewOnceEventIDs
        self.rawItems = initialItems
        self.items = Self.sorted(initialItems, by: .newest)
    }

    /// Resets paging and loads the first page for the current `tab`, `sentBy`, `query`, and `roomID`.
    public func refresh() async {
        nextCursor = nil
        hasMore = false
        rawItems = []
        items = []
        selectedEventIDs.removeAll()
        await fetchPage(cursor: nil, append: false)
    }

    /// Loads the next page using `nextCursor` when `hasMore` is true.
    public func loadNextPage() async {
        guard hasMore, !isLoading, let cursor = nextCursor, !cursor.isEmpty else { return }
        await fetchPage(cursor: cursor, append: true)
    }

    /// Toggles selection of `eventID` for batch download or deletion.
    public func toggleSelected(_ eventID: String) {
        guard AppLockGate.shared.canPerform(.other, lifecycle: appModel.lifecycle) else { return }
        if selectedEventIDs.contains(eventID) {
            selectedEventIDs.remove(eventID)
        } else {
            selectedEventIDs.insert(eventID)
        }
    }

    /// Clears all selected items.
    public func clearSelection() {
        guard AppLockGate.shared.canPerform(.other, lifecycle: appModel.lifecycle) else { return }
        selectedEventIDs.removeAll()
    }

    /// Deletes all selected items: calls `message.unsend` when `forEveryone && item.mine`, otherwise `message.deleteForMe`.
    public func deleteSelected(forEveryone: Bool) async {
        guard AppLockGate.shared.canPerform(.other, lifecycle: appModel.lifecycle) else { return }
        guard let client = appModel.client else { return }
        let selected = items.filter { selectedEventIDs.contains($0.eventID) }
        guard !selected.isEmpty else { return }

        var deletedIDs = Set<String>()
        for hit in selected {
            guard !hit.roomID.hasPrefix("merge:") else { continue }
            let params = DeleteMessageParams(roomID: hit.roomID, eventID: hit.eventID)
            let method = (forEveryone && hit.mine) ? "message.unsend" : "message.deleteForMe"
            if (try? await client.call(method, params) as Empty) != nil {
                deletedIDs.insert(hit.eventID)
            }
        }
        if !deletedIDs.isEmpty {
            rawItems.removeAll { deletedIDs.contains($0.eventID) }
            items = Self.sorted(rawItems, by: sortOrder)
            selectedEventIDs.subtract(deletedIDs)
        }
    }

    /// Downloads all selected local-store attachments via `AttachmentDownloader`.
    @discardableResult
    public func downloadSelected(using downloader: AttachmentDownloader) -> [URL] {
        guard AppLockGate.shared.canPerform(.download, lifecycle: appModel.lifecycle) else { return [] }
        let selected = items.filter { selectedEventIDs.contains($0.eventID) && !$0.viewOnce }
        var urls: [URL] = []
        for hit in selected where isLocalMediaStorePath(hit.mediaPath) {
            if let saved = try? downloader.download(sourcePath: hit.mediaPath, suggestedName: hit.fileName) {
                urls.append(saved)
            }
        }
        return urls
    }

    // MARK: - Private

    private struct DeleteMessageParams: Encodable {
        let roomID: String
        let eventID: String

        enum CodingKeys: String, CodingKey {
            case roomID = "room_id"
            case eventID = "event_id"
        }
    }

    private struct WireSearchResponse: Decodable {
        struct Page: Decodable {
            let hits: [MediaHit]
            let nextCursor: String?

            enum CodingKeys: String, CodingKey {
                case hits
                case nextCursor = "next_cursor"
            }
        }

        let media: Page?
        let messages: Page?
    }

    private func scopedRoomIDs() -> [String]? {
        guard let roomID, !roomID.isEmpty else { return nil }
        let expanded = appModel.scopeRoomIDs(for: roomID).filter { !$0.hasPrefix("merge:") }
        return expanded.isEmpty ? nil : expanded
    }

    private func isExcludedViewOnce(_ hit: MediaHit) -> Bool {
        if hit.viewOnce { return true }
        if knownViewOnceEventIDs.contains(hit.eventID) { return true }
        if let conversation, conversation.isViewOnceEvent(hit.eventID) {
            return true
        }
        return false
    }

    private func fetchPage(cursor: String?, append: Bool) async {
        guard let client = appModel.client else { return }
        isLoading = true
        defer { isLoading = false }

        let senderFilter: String?
        switch sentBy {
        case .all:
            senderFilter = nil
        case .you:
            senderFilter = "me"
        case .others:
            senderFilter = "others"
        }

        let kinds: [String]
        let sections: [SearchSectionName]
        switch tab {
        case .media:
            kinds = ["image", "video", "sticker"]
            sections = [.media]
        case .links:
            kinds = ["link"]
            sections = [.messages]
        case .docs:
            kinds = ["file", "audio"]
            sections = [.messages]
        }

        let filters = SearchFilters(
            roomIDs: scopedRoomIDs(),
            sender: senderFilter,
            kinds: kinds
        )
        let params = SearchParams(
            text: query.trimmingCharacters(in: .whitespacesAndNewlines),
            sections: sections,
            filters: filters,
            cursor: cursor,
            limit: min(max(1, pageLimit), 50)
        )

        guard let response: WireSearchResponse = try? await client.call("search.query", params) else {
            return
        }
        let page = response.media ?? response.messages
        let incoming = (page?.hits ?? []).filter { hit in
            guard !isExcludedViewOnce(hit) else { return false }
            if tab == .media || tab == .docs {
                if !hit.mediaPath.isEmpty && !isLocalMediaStorePath(hit.mediaPath) {
                    return false
                }
            }
            return true
        }

        if append {
            let existingIDs = Set(rawItems.map(\.eventID))
            for hit in incoming where !existingIDs.contains(hit.eventID) {
                rawItems.append(hit)
            }
        } else {
            rawItems = incoming
        }
        nextCursor = page?.nextCursor
        hasMore = (page?.nextCursor?.isEmpty == false)
        items = Self.sorted(rawItems, by: sortOrder)
    }

    private static func sorted(_ hits: [MediaHit], by order: SortOrder) -> [MediaHit] {
        hits.sorted { lhs, rhs in
            if lhs.ts != rhs.ts {
                return order == .newest ? (lhs.ts > rhs.ts) : (lhs.ts < rhs.ts)
            }
            if lhs.seq != rhs.seq {
                return order == .newest ? (lhs.seq > rhs.seq) : (lhs.seq < rhs.seq)
            }
            return order == .newest ? (lhs.eventID > rhs.eventID) : (lhs.eventID < rhs.eventID)
        }
    }
}
