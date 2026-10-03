// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package struct NotchQueueItem: Equatable, Identifiable {
    package let id: String
    package let offset: Int
    package let title: String
    package let artist: String
    package let duration: Double
    package var artwork: Data? = nil

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, offset: Int, title: String, artist: String, duration: Double, artwork: Data? = nil) {
        self.id = id
        self.offset = offset
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artwork = artwork
    }
}

package struct NotchQueueSnapshot: Equatable {
    package let requestID: UUID
    package let currentIdentifier: String
    package let pid: Int32
    package let items: [NotchQueueItem]
    package let canPlay: Bool
    package var currentArtwork: Data? = nil

    // Spelled out because a memberwise initializer never leaves its module.
    package init(requestID: UUID, currentIdentifier: String, pid: Int32, items: [NotchQueueItem], canPlay: Bool, currentArtwork: Data? = nil) {
        self.requestID = requestID
        self.currentIdentifier = currentIdentifier
        self.pid = pid
        self.items = items
        self.canPlay = canPlay
        self.currentArtwork = currentArtwork
    }
}

package enum NotchQueueSupport {
    package static let maximumItems = NotchQueueSelection.maximumItems
    package static let maximumArtworkBytes = 64 * 1_024

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchQueue.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchQueueEnabled)
            && NotchSupport.modules(in: defaults).contains(.music)
    }

    package static func decode(_ object: [String: Any], requestID: UUID, playback: NotchPlayback) -> NotchQueueSnapshot? {
        guard object["queueRequest"] as? String == requestID.uuidString,
              let current = object["currentIdentifier"] as? String, NotchPlaybackCommand.validIdentifier(current),
              current == playback.itemIdentifier,
              let rawPID = object["pid"] as? NSNumber, CFGetTypeID(rawPID) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: rawPID.doubleValue), pid > 0, pid == playback.track.appPID,
              object["queueAvailable"] as? Bool == true,
              let rows = object["queueItems"] as? [[String: Any]], rows.count <= maximumItems else { return nil }
        var ids = Set<String>()
        var offsets = Set<Int>()
        var items: [NotchQueueItem] = []
        for row in rows {
            guard let id = row["id"] as? String, NotchPlaybackCommand.validIdentifier(id),
                  id != current, ids.insert(id).inserted,
                  let offset = row["offset"] as? Int, (1...maximumItems).contains(offset), offsets.insert(offset).inserted,
                  let title = row["title"] as? String, !title.isEmpty, title.utf8.count <= 4096 else { return nil }
            let artist = String((row["artist"] as? String ?? "").prefix(1024))
            let duration = row["duration"] as? Double ?? 0
            guard duration.isFinite, (0...604_800).contains(duration) else { return nil }
            items.append(NotchQueueItem(id: id, offset: offset, title: title, artist: artist, duration: duration,
                                        artwork: artwork(row["artworkBase64"])))
        }
        return NotchQueueSnapshot(requestID: requestID, currentIdentifier: current, pid: pid,
                                  items: items.sorted { $0.offset < $1.offset },
                                  canPlay: playback.canSendCommandsDirectly && object["queueCanPlay"] as? Bool == true,
                                  currentArtwork: artwork(object["currentArtworkBase64"]))
    }

    package static func awaitsSongQueue(_ object: [String: Any], requestID: UUID, playback: NotchPlayback) -> Bool {
        guard object["queueRequest"] as? String == requestID.uuidString,
              let anchored = object["currentIdentifier"] as? String, NotchPlaybackCommand.validIdentifier(anchored),
              let current = playback.itemIdentifier, anchored != current,
              let rawPID = object["pid"] as? NSNumber, CFGetTypeID(rawPID) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: rawPID.doubleValue), pid > 0 else { return false }
        return pid == playback.track.appPID
    }

    private static func artwork(_ value: Any?) -> Data? {
        guard let text = value as? String, text.utf8.count <= maximumArtworkBytes / 3 * 4 + 4,
              let data = Data(base64Encoded: text), !data.isEmpty, data.count <= maximumArtworkBytes else { return nil }
        return data
    }
}

package struct NotchQueueCovers<Image> {
    private struct Key: Hashable {
        let pid: Int32
        let item: String

        // Spelled out because a memberwise initializer never leaves its module.
        package init(pid: Int32, item: String) {
            self.pid = pid
            self.item = item
        }
    }
    private var entries: [Key: (data: Data, image: Image)] = [:]
    package private(set) var images: [String: Image] = [:]

    package mutating func update(_ queue: NotchQueueSnapshot?, decode: (Data) -> Image?) {
        guard let queue else { images = [:]; return }
        let songs = [(queue.currentIdentifier, queue.currentArtwork)] + queue.items.map { ($0.id, $0.artwork) }
        var kept: [Key: (data: Data, image: Image)] = [:]
        for (item, data) in songs {
            let key = Key(pid: queue.pid, item: item)
            let known = entries[key]
            if let data, data != known?.data, let image = decode(data) {
                kept[key] = (data, image)
            } else if let known {
                kept[key] = known
            }
        }
        var shown: [String: Image] = [:]
        for item in queue.items { shown[item.id] = kept[Key(pid: queue.pid, item: item.id)]?.image }
        entries = kept
        images = shown
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}
