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
}
