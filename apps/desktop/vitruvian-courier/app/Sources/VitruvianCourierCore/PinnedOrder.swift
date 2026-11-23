// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Pure ordering helpers for drag-to-reorder in the pinned chats strip.
public enum PinnedOrder {
    /// Returns `order` with `id` moved to `target`'s position.
    ///
    /// Returns `order` unchanged when `id == target` or either ID is absent from `order`.
    public static func moving(_ id: String, onto target: String, in order: [String]) -> [String] {
        guard id != target,
              let fromIndex = order.firstIndex(of: id),
              let toIndex = order.firstIndex(of: target) else {
            return order
        }
        var updated = order
        let moved = updated.remove(at: fromIndex)
        updated.insert(moved, at: toIndex)
        return updated
    }

    /// Returns `rows` ordered by `draftOrder` when present.
    ///
    /// Named rows appear first in `draftOrder`'s order (deduplicated); unknown IDs in `draftOrder` are ignored;
    /// rows in `rows` not named in `draftOrder` are appended in their existing order.
    public static func ordered<T: Identifiable>(_ rows: [T], by draftOrder: [T.ID]?) -> [T] where T.ID: Hashable {
        guard let draftOrder else { return rows }
        var byID: [T.ID: T] = [:]
        byID.reserveCapacity(rows.count)
        for row in rows where byID[row.id] == nil {
            byID[row.id] = row
        }
        var seen = Set<T.ID>()
        var result: [T] = []
        result.reserveCapacity(rows.count)
        for id in draftOrder {
            if let row = byID[id], seen.insert(id).inserted {
                result.append(row)
            }
        }
        for row in rows where seen.insert(row.id).inserted {
            result.append(row)
        }
        return result
    }

    /// The tile whose frame holds `point`, if any (`frames` by row ID, in the same space as `point`). Between tiles
    /// (the grid's gaps) there is none, and the order stays as it is.
    public static func tile(at point: CGPoint, in frames: [String: CGRect]) -> String? {
        frames.first { $0.value.contains(point) }?.key
    }
}

/// What a drag in the pinned strip is doing: the tile it started from, the tile shown faded, and the order the tiles
/// are drawn in while it lasts. Kept apart from the view so every step (start, move, leave, drop, cancel) is tested.
public struct PinnedDragState: Equatable {
    /// The tile the last drag started from. Kept when the drag leaves the strip (it may come back) and replaced by
    /// the next drag; a stale one is harmless, since a drop needs a drag carrying the pinned-chat type.
    public private(set) var sourceID: String?
    /// The tile drawn faded: the dragged one, while it is over the strip.
    public private(set) var fadedID: String?
    /// The order the tiles are drawn in while dragging (or until a dropped order arrives); nil: the rows' own.
    public private(set) var draft: [String]?

    public init() {}

    public var canDrop: Bool { sourceID != nil }

    public mutating func begin(_ id: String, order: [String]) {
        sourceID = id
        fadedID = id
        draft = order
    }

    /// Over the strip, with `target` the tile under the pointer (nil in a gap): the dragged tile takes its place.
    /// Returns whether the drawn order changed.
    @discardableResult
    public mutating func move(over target: String?, order: [String]) -> Bool {
        guard let sourceID else { return false }
        fadedID = sourceID
        guard let target else { return false }
        let base = draft ?? order
        let next = PinnedOrder.moving(sourceID, onto: target, in: base)
        guard next != base else { return false }
        draft = next
        return true
    }

    /// Out of the strip, or the drag was cancelled there: the tiles go back and the faded one comes back.
    public mutating func exit() {
        fadedID = nil
        draft = nil
    }

    /// Dropped on the strip: the order to save, or nil when there is nothing to save. The drawn order stays until the
    /// saved one arrives (`rowsChanged` or `committed`), so the tiles don't jump back meanwhile.
    public mutating func drop(order: [String]) -> [String]? {
        defer {
            sourceID = nil
            fadedID = nil
        }
        guard sourceID != nil, let draft, draft != order else {
            self.draft = nil
            return nil
        }
        return draft
    }

    /// The save finished: the rows' own order takes over, unless another drag has started since.
    public mutating func committed() {
        if sourceID == nil { draft = nil }
    }

    /// The rows changed from outside: their order takes over, and a drag from a tile that is gone ends.
    public mutating func rowsChanged(_ ids: [String]) {
        draft = nil
        if let sourceID, !ids.contains(sourceID) {
            self.sourceID = nil
            fadedID = nil
        }
    }

    /// Dragging stopped being allowed (selecting, locked) or the strip went away.
    public mutating func cancel() {
        self = PinnedDragState()
    }
}
