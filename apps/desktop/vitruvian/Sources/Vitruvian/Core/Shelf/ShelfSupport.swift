// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import UniformTypeIdentifiers

package enum ShelfSelectionSupport {
    /// Escape clears the Shelf selection only when pressed on its own. Keeping
    /// modifier-bearing variants available avoids swallowing future shortcuts.
    package static func isClearSelectionShortcut(keyCode: UInt16,
                                         hasSelectionModifiers: Bool) -> Bool {
        keyCode == 53 && !hasSelectionModifiers
    }

    /// The visible ids covered by a shift-click, from the last tile the user
    /// touched to the clicked tile, inclusive and in either direction.
    package static func rangeSelectionIDs<ID: Equatable>(allIDs: [ID],
                                                 anchorID: ID?,
                                                 targetID: ID) -> [ID] {
        guard let target = allIDs.firstIndex(of: targetID) else { return [] }
        let anchor = anchorID.flatMap { allIDs.firstIndex(of: $0) } ?? target
        let bounds = min(anchor, target)...max(anchor, target)
        return Array(allIDs[bounds])
    }
}

/// Tracks the shelf shortcut's asynchronous Finder selection read. Every press
/// takes a new ticket, and a later press, clearing the Shelf or turning it off
/// retires the older one, so a slow Finder or a permission prompt answering late
/// can neither add a stale selection nor toggle the Shelf after the fact.
package struct ShelfShortcutSelectionRequests {
    package enum Outcome: Equatable {
        case discard
        case toggle
        case add([URL])
    }

    private var lastTicket: UInt64 = 0
    private var pendingTicket: UInt64?

    package var hasPending: Bool { pendingTicket != nil }

    package mutating func begin() -> UInt64 {
        lastTicket &+= 1
        pendingTicket = lastTicket
        return lastTicket
    }

    package mutating func invalidate() {
        pendingTicket = nil
    }

    /// Settles a reply once. `stillAllowed` is the feature state rechecked when
    /// the reply arrives, not the state from when the shortcut was pressed.
    /// Files the shelf already holds are left out, so pressing the shortcut
    /// again on the same selection toggles the shelf instead of shelving the
    /// same files twice. Finder stays in front while the shelf is up, so that
    /// second press is the ordinary way to close it.
    package mutating func resolve(_ ticket: UInt64, urls: [URL], stillAllowed: Bool,
                          shelvedPaths: Set<String> = []) -> Outcome {
        guard ticket == pendingTicket else { return .discard }
        pendingTicket = nil
        guard stillAllowed else { return .discard }
        let fresh = urls.filter { !shelvedPaths.contains($0.standardizedFileURL.path) }
        return fresh.isEmpty ? .toggle : .add(fresh)
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}

/// A Shelf item reduced to what revealing needs: identity and nesting. A pure
/// stand-in for the service's item tree, like ShelfEdgeScreen is for NSScreen,
/// so the rules below stay in the unit harness.
package struct ShelfRevealNode: Equatable {
    package let id: UUID
    package let children: [ShelfRevealNode]

    package init(id: UUID, children: [ShelfRevealNode] = []) {
        self.id = id
        self.children = children
    }
}

package enum ShelfRevealSupport {
    /// The item the Shelf should scroll to when `target` is added. A merged
    /// file becomes a child of a pile, and a collapsed pile draws no tile for
    /// its children, so the answer is the deepest ancestor that is drawn:
    /// the item itself when every ancestor is expanded, the outermost
    /// collapsed pile otherwise, and nothing when the id is not on the shelf.
    package static func visibleAncestorID(of target: UUID,
                                  in nodes: [ShelfRevealNode],
                                  expanded: Set<UUID>) -> UUID? {
        for node in nodes {
            if node.id == target { return node.id }
            guard !node.children.isEmpty else { continue }
            guard let deeper = visibleAncestorID(of: target,
                                                 in: node.children,
                                                 expanded: expanded) else { continue }
            return expanded.contains(node.id) ? deeper : node.id
        }
        return nil
    }

    /// Whether this add is one the Shelf hasn't already scrolled to. Keyed
    /// on the add serial rather than the resolved target: the target alone
    /// changes when a pile is expanded or collapsed with nothing added,
    /// and repeats when two files land in the same collapsed pile back to
    /// back, either of which would misfire a target-keyed dedup.
    package static func shouldReveal(serial: Int, lastHonored: Int?) -> Bool {
        serial != lastHonored
    }
}

package enum ShelfTileLayout {
    /// How many tile columns fit a given width, never fewer than one so a
    /// narrow panel still lays out.
    package static func columnCount(contentWidth: CGFloat,
                            tileWidth: CGFloat,
                            spacing: CGFloat,
                            inset: CGFloat) -> Int {
        let usable = contentWidth - inset * 2 + spacing
        return max(1, Int(usable / (tileWidth + spacing)))
    }

    /// How many tile rows fit a given height, for a strip that flows sideways.
    package static func rowCount(contentHeight: CGFloat,
                         tileHeight: CGFloat,
                         spacing: CGFloat,
                         inset: CGFloat) -> Int {
        let usable = contentHeight - inset * 2 + spacing
        return max(1, Int(usable / (tileHeight + spacing)))
    }

    /// Where the tile at `index` sits when tiles fill each column top to
    /// bottom and continue to the right.
    package static func sidewaysTileFrame(index: Int,
                                  rows: Int,
                                  tileSize: CGSize,
                                  spacing: CGFloat,
                                  inset: CGFloat) -> CGRect {
        let safeRows = max(1, rows)
        let column = index / safeRows
        let row = index % safeRows
        return CGRect(x: inset + CGFloat(column) * (tileSize.width + spacing),
                      y: inset + CGFloat(row) * (tileSize.height + spacing),
                      width: tileSize.width,
                      height: tileSize.height)
    }

    /// The document size for a sideways strip: wide enough for every column
    /// and tall enough for every row, and never smaller than the visible area.
    package static func sidewaysDocumentSize(itemCount: Int,
                                     rows: Int,
                                     visibleSize: CGSize,
                                     tileSize: CGSize,
                                     spacing: CGFloat,
                                     inset: CGFloat) -> CGSize {
        let safeRows = max(1, rows)
        let columns = max(1, Int(ceil(Double(itemCount) / Double(safeRows))))
        let filledRows = min(safeRows, max(1, itemCount))
        let width = inset * 2 + CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing
        let height = inset * 2 + CGFloat(filledRows) * tileSize.height + CGFloat(filledRows - 1) * spacing
        return CGSize(width: max(width, visibleSize.width), height: max(height, visibleSize.height))
    }

    /// Where the tile at `index` sits in the flipped document view.
    package static func tileFrame(index: Int,
                          columns: Int,
                          tileSize: CGSize,
                          spacing: CGFloat,
                          inset: CGFloat) -> CGRect {
        let safeColumns = max(1, columns)
        let column = index % safeColumns
        let row = index / safeColumns
        return CGRect(x: inset + CGFloat(column) * (tileSize.width + spacing),
                      y: inset + CGFloat(row) * (tileSize.height + spacing),
                      width: tileSize.width,
                      height: tileSize.height)
    }
}

package enum ShelfInteractionSupport {
    /// App exclusions only suppress automatic Shelf appearances. A deliberate
    /// shortcut or "Open now" action remains an escape hatch everywhere.
    package static func allowsAutomaticOpen(sourceBundleIdentifier: String?,
                                    excludedBundleIdentifiers: Set<String>) -> Bool {
        guard let sourceBundleIdentifier, !sourceBundleIdentifier.isEmpty else { return true }
        return !excludedBundleIdentifiers.contains(sourceBundleIdentifier)
    }

    /// Whether the gesture in flight drags real content, as opposed to moving
    /// or resizing a window. The drag pasteboard retains the previous drag's
    /// items indefinitely, so retained content alone proves nothing: only a
    /// change-count bump during the current gesture makes it current. Dock
    /// stacks can publish the contents before the mouse-down is seen, so a
    /// gesture in the Dock counts from the end of the previous gesture
    /// instead. It still needs a bump, so holding or dragging a Dock icon over
    /// content an earlier drag left behind is not a content drag (#2212).
    /// Either way the pasteboard must hold something the Shelf can keep; the
    /// check stays lazy because most dragged events resolve on the cheap
    /// change count alone.
    package static func isContentDrag(gestureChangeCount: Int,
                              restingChangeCount: Int,
                              changeCount: Int,
                              beganInDock: Bool,
                              hasDroppableContent: () -> Bool) -> Bool {
        let baseline = beganInDock ? restingChangeCount : gestureChangeCount
        guard changeCount != baseline else { return false }
        return hasDroppableContent()
    }

    /// A successful drag that really left the Shelf can dismiss it. Cancelled
    /// drags and internal merges never do, and pinning always wins.
    package static func shouldCloseAfterDrag(dropAccepted: Bool,
                                     draggedItemCount: Int,
                                     closeAfterDrop: Bool,
                                     pinned: Bool) -> Bool {
        dropAccepted && draggedItemCount > 0 && closeAfterDrop && !pinned
    }

    /// Keeping an item after it was dragged out is safe only when the source
    /// offers copy semantics; the live AppKit source uses this preference to
    /// avoid a target moving the underlying file away from its persisted URL.
    package static func shouldRemoveAfterDrag(dropAccepted: Bool,
                                      draggedItemCount: Int,
                                      removeAfterDrop: Bool) -> Bool {
        dropAccepted && draggedItemCount > 0 && removeAfterDrop
    }

    /// The dragged tiles that may leave the Shelf after a drop. A pinned item,
    /// or anything inside a pinned pile, is reused across sessions and stays.
    package static func removableAfterDrag(_ draggedIDs: [UUID], protectedIDs: Set<UUID>) -> [UUID] {
        draggedIDs.filter { !protectedIDs.contains($0) }
    }

    /// A pinned item is dragged out again and again, so a destination must
    /// never be offered a move: it would take the file away from the Shelf.
    package static func offersMoveOutside(removeAfterDrop: Bool, dragIncludesPinned: Bool) -> Bool {
        removeAfterDrop && !dragIncludesPinned
    }
}

/// Types accepted by the native shelf drop targets.
package enum ShelfPasteboardSupport {
    /// The files a pasteboard holds, each once, from file URLs or the
    /// older filenames list.
    package static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [NSURL],
           !urls.isEmpty {
            return unique(urls.map { $0 as URL }.filter(\.isFileURL))
        }
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           !paths.isEmpty {
            return unique(paths.map { URL(fileURLWithPath: $0) })
        }
        return []
    }

    /// Each file once, by its standardized path.
    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Orders a mixed drop by pasteboard position. Receivers follow the
    /// promised pasteboard items in order; a receiver without one goes last.
    package static func mergedItemIndices(companionPositions: [Int], receiverIndices: [Int],
                                  promisePositions: [Int]) -> [Int] {
        let positions = companionPositions + receiverIndices.map { index in
            promisePositions.indices.contains(index) ? promisePositions[index] : Int.max
        }
        return positions.indices.sorted {
            positions[$0] == positions[$1] ? $0 < $1 : positions[$0] < positions[$1]
        }
    }

    package static let filePromiseTypeIdentifiers: Set<String> = {
        var ids = Set(NSFilePromiseReceiver.readableDraggedTypes)
        ids.formUnion(["Apple files promise pasteboard type",
                       "com.apple.pasteboard.promised-file-url",
                       "com.apple.pasteboard.promised-file-content-type"])
        return ids
    }()

    private static let directDroppableTypes: Set<String> = [
        NSPasteboard.PasteboardType.fileURL.rawValue,
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        NSPasteboard.PasteboardType.png.rawValue,
        UTType.gif.identifier,
        UTType.fileURL.identifier,
        UTType.image.identifier,
        UTType.url.identifier,
        UTType.text.identifier,
        UTType.plainText.identifier,
        "NSFilenamesPboardType",
        "NSURLPboardType"
    ]

    private static let supportedUTTypes: [UTType] = [
        .fileURL, .gif, .image, .url, .text, .plainText
    ]

    package static func isFilePromiseType(_ rawValue: String) -> Bool {
        filePromiseTypeIdentifiers.contains(rawValue)
    }

    package static func isDroppablePasteboardType(_ rawValue: String) -> Bool {
        if isFilePromiseType(rawValue) { return true }
        if directDroppableTypes.contains(rawValue) { return true }
        guard let utType = UTType(rawValue) else { return false }
        return supportedUTTypes.contains { utType.conforms(to: $0) }
    }


}

/// A leaf item's kind, reduced to what the pile-breakdown tooltip needs. A
/// pure stand-in for ShelfService.Item's payload, like ShelfEdgeScreen is
/// for NSScreen, so this stays testable without depending on Item.
package enum ShelfTooltipLeafKind {
    case image, file, note, link
}

/// How many leaves of each kind a pile holds, for its tooltip breakdown.
package struct ShelfTooltipPileBreakdown: Equatable {
    package var images = 0
    package var files = 0
    package var notes = 0
    package var links = 0

    package var total: Int { images + files + notes + links }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(images: Int = 0, files: Int = 0, notes: Int = 0, links: Int = 0) {
        self.images = images
        self.files = files
        self.notes = notes
        self.links = links
    }
}

/// The localized words the pile breakdown needs (this app has no CLDR-style
/// pluralization, so each form is its own string): one for a count of one, one
/// for two through four where a language asks for it, and one for the rest.
/// The items count has no singular because a pile always holds two or more.
package struct ShelfTooltipStrings {
    package let itemsFormat: String
    package let itemsFew: String
    package let imageSingular: String
    package let imageFew: String
    package let imagePlural: String
    package let fileSingular: String
    package let fileFew: String
    package let filePlural: String
    package let noteSingular: String
    package let noteFew: String
    package let notePlural: String
    package let linkSingular: String
    package let linkFew: String
    package let linkPlural: String
    /// How the language agrees a counted noun with its number.
    package let agreement: CountAgreement

    /// The form a count asks for. Russian agrees by the number's last digits:
    /// one for 1, 21, 31 but not 11; the middle form for 2 through 4, 22
    /// through 24 but not 12 through 14; the last for everything else.
    /// Slovak reads the whole number instead, so only 1 and only 2 through 4
    /// leave the last form, and 21 and 22 stay with it.
    package enum Form { case one, few, many }

    package func form(for count: Int) -> Form {
        let magnitude = abs(count)
        switch agreement {
        case .oneAndMany:
            return magnitude == 1 ? .one : .many
        case .byWholeNumber:
            if magnitude == 1 { return .one }
            return (2...4).contains(magnitude) ? .few : .many
        case .byLastDigits:
            if (11...14).contains(magnitude % 100) { return .many }
            switch magnitude % 10 {
            case 1: return .one
            case 2, 3, 4: return .few
            default: return .many
            }
        }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(itemsFormat: String, itemsFew: String, imageSingular: String, imageFew: String, imagePlural: String, fileSingular: String, fileFew: String, filePlural: String, noteSingular: String, noteFew: String, notePlural: String, linkSingular: String, linkFew: String, linkPlural: String, agreement: CountAgreement) {
        self.itemsFormat = itemsFormat
        self.itemsFew = itemsFew
        self.imageSingular = imageSingular
        self.imageFew = imageFew
        self.imagePlural = imagePlural
        self.fileSingular = fileSingular
        self.fileFew = fileFew
        self.filePlural = filePlural
        self.noteSingular = noteSingular
        self.noteFew = noteFew
        self.notePlural = notePlural
        self.linkSingular = linkSingular
        self.linkFew = linkFew
        self.linkPlural = linkPlural
        self.agreement = agreement
    }
}

package enum ShelfTooltipSupport {
    /// Long enough to show a real paragraph, short enough that a huge paste
    /// doesn't produce an unusably huge tooltip.
    package static let textCap = 500

    /// A file tile's tooltip: its name, and the system's own Kind string on
    /// a second line when one was found. A blank or missing kind (the file
    /// went away, or the lookup failed for any reason) is not worth
    /// surfacing as an error to someone just hovering, so it falls back to
    /// the name alone rather than showing a blank second line.
    package static func text(forFileNamed title: String, resolvedKind: String?) -> String {
        guard let resolvedKind, !resolvedKind.isEmpty else { return title }
        return "\(title)\n\(resolvedKind)"
    }

    /// A text tile's tooltip: the full content, not the truncated preview
    /// the tile's own title already shows. Trimmed the same way the title
    /// preview is, since the stored payload keeps the original whitespace
    /// verbatim but that whitespace carries no identifying information.
    package static func text(forText string: String, cap: Int = textCap) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > cap else { return trimmed }
        return String(trimmed.prefix(cap)) + "…"
    }

    /// A link tile's tooltip: the full URL. The tile's own title is only
    /// the host, so this is where the rest of it becomes visible. Capped
    /// the same way pasted text is: an unbroken query token can otherwise
    /// produce an unusably tall popover with no line breaks to wrap on.
    package static func text(forLink url: URL, cap: Int = textCap) -> String {
        let string = url.absoluteString
        guard string.count > cap else { return string }
        return String(string.prefix(cap)) + "…"
    }

    /// Counts a pile's flattened leaves by kind.
    package static func breakdown(of kinds: [ShelfTooltipLeafKind]) -> ShelfTooltipPileBreakdown {
        var result = ShelfTooltipPileBreakdown()
        for kind in kinds {
            switch kind {
            case .image: result.images += 1
            case .file: result.files += 1
            case .note: result.notes += 1
            case .link: result.links += 1
            }
        }
        return result
    }

    /// A pile's tooltip: the total, then a breakdown of only the kinds it
    /// actually has, each in the grammatically correct singular or plural
    /// form for its own count. A pile with nothing in it (should not occur
    /// in practice) still returns a plain string rather than crashing or
    /// leaving a dangling colon with nothing after it.
    package static func text(forPile breakdown: ShelfTooltipPileBreakdown, strings: ShelfTooltipStrings) -> String {
        var parts: [String] = []
        func worded(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
            switch strings.form(for: count) {
            case .one: return String(format: one, count)
            case .few: return String(format: few, count)
            case .many: return String(format: many, count)
            }
        }
        if breakdown.images > 0 {
            parts.append(worded(breakdown.images,
                                strings.imageSingular, strings.imageFew, strings.imagePlural))
        }
        if breakdown.files > 0 {
            parts.append(worded(breakdown.files,
                                strings.fileSingular, strings.fileFew, strings.filePlural))
        }
        if breakdown.notes > 0 {
            parts.append(worded(breakdown.notes,
                                strings.noteSingular, strings.noteFew, strings.notePlural))
        }
        if breakdown.links > 0 {
            parts.append(worded(breakdown.links,
                                strings.linkSingular, strings.linkFew, strings.linkPlural))
        }
        // A pile always holds two or more, so the items count only ever needs
        // the middle form or the last one.
        let itemsText = strings.form(for: breakdown.total) == .few
            ? String(format: strings.itemsFew, breakdown.total)
            : String(format: strings.itemsFormat, breakdown.total)
        guard !parts.isEmpty else { return itemsText }
        return "\(itemsText): \(parts.joined(separator: ", "))"
    }
}

/// Which side of the screen a drag is being aimed at, for the "open near a
/// screen edge" trigger. Only left and right: top and bottom already belong
/// to the menu bar and the Dock, wherever it sits.
package enum ShelfEdge: Equatable {
    case left, right
}

/// A resolved edge match: which side, and the screen it belongs to, kept
/// together so a later retreat check tests the same edge instead of
/// accidentally resolving a different screen's edge.
package struct ShelfEdgeMatch: Equatable {
    package let edge: ShelfEdge
    package let screen: CGRect

    // Spelled out because a memberwise initializer never leaves its module.
    package init(edge: ShelfEdge, screen: CGRect) {
        self.edge = edge
        self.screen = screen
    }
}

/// A screen's physical frame paired with its visible frame (the physical
/// frame minus the menu bar and Dock), so `ShelfEdgeDragSupport.match` can
/// tell "near the physical edge" apart from "over the Dock's own reserved
/// space" when a Dock is mounted on the left or right. When nothing is
/// reserved there (Dock at the bottom or auto-hidden), `visibleFrame`'s
/// horizontal bounds equal `frame`'s and this carries no effect.
package struct ShelfEdgeScreen: Equatable {
    package let frame: CGRect
    package let visibleFrame: CGRect

    // Spelled out because a memberwise initializer never leaves its module.
    package init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

package enum ShelfEdgeDragSupport {
    /// How close the pointer has to be to a screen's outer edge to count as
    /// heading for it.
    package static let triggerDistance: CGFloat = 200
    /// Wider than the trigger distance on purpose: the boundary needs its
    /// own hysteresis, or hovering right at the edge would flicker between
    /// shown and retracted.
    package static let retreatDistance: CGFloat = 330
    /// How long the pointer has to stay within the trigger distance before
    /// it counts as heading for the edge, so a fast pass through the zone
    /// (e.g. flicking the pointer past it on the way elsewhere) does not
    /// fire. `match`'s Dock-margin exclusion keeps parking on a Dock icon
    /// from triggering it at all; a slow approach through the rest of the
    /// zone before ever reaching the Dock can still dwell long enough to
    /// fire, the same as approaching any other point near the edge would.
    package static let dwell: TimeInterval = 0.15

    /// The left or right edge of whichever screen the point is closest to,
    /// within `distance` of that edge, or nil when nothing qualifies. A
    /// seam shared by two adjacent displays never counts as either
    /// screen's own outer edge, so a drag crossing between displays there
    /// is never caught. A point resting inside a side-mounted Dock's own
    /// reserved margin (`frame` minus `visibleFrame`, horizontally) never
    /// counts either, so parking over a Dock icon to drop there doesn't
    /// also peek the shelf.
    package static func match(at point: CGPoint, screens: [ShelfEdgeScreen], distance: CGFloat) -> ShelfEdgeMatch? {
        let ordered = screens.enumerated().sorted {
            distanceSquared(from: point, to: $0.element.frame) < distanceSquared(from: point, to: $1.element.frame)
        }
        for (index, screen) in ordered {
            let frame = screen.frame
            guard frame.width > 0, frame.height > 0,
                  point.x >= frame.minX - distance, point.x <= frame.maxX + distance,
                  point.y >= frame.minY - distance, point.y <= frame.maxY + distance
            else { continue }
            let others = screens.enumerated().compactMap { $0.offset == index ? nil : $0.element.frame }
            let nearLeft = point.x <= frame.minX + distance
                && point.x >= screen.visibleFrame.minX
                && !hasNeighbor(at: CGPoint(x: frame.minX - distance - 1, y: point.y), frames: others)
            if nearLeft { return ShelfEdgeMatch(edge: .left, screen: frame) }
            let nearRight = point.x >= frame.maxX - distance
                && point.x <= screen.visibleFrame.maxX
                && !hasNeighbor(at: CGPoint(x: frame.maxX + distance + 1, y: point.y), frames: others)
            if nearRight { return ShelfEdgeMatch(edge: .right, screen: frame) }
        }
        return nil
    }

    /// Whether the point is still within `distance` of the same edge and
    /// screen an earlier match resolved, without re-resolving which screen
    /// or edge is nearest now. Used to check retreat against the edge that
    /// is actually showing, not whichever edge happens to be closest.
    package static func stillNear(_ match: ShelfEdgeMatch, point: CGPoint, distance: CGFloat) -> Bool {
        let withinHeight = point.y >= match.screen.minY - distance && point.y <= match.screen.maxY + distance
        guard withinHeight else { return false }
        switch match.edge {
        case .left: return point.x <= match.screen.minX + distance
        case .right: return point.x >= match.screen.maxX - distance
        }
    }

    /// Whether a dwell that began at `since` has lasted long enough, given
    /// the current time, to count as heading for the edge rather than
    /// passing near it.
    package static func hasDwelled(since: TimeInterval, now: TimeInterval, required: TimeInterval = dwell) -> Bool {
        now - since >= required
    }

    private static func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    private static func hasNeighbor(at point: CGPoint, frames: [CGRect]) -> Bool {
        frames.contains { $0.insetBy(dx: -1, dy: -1).contains(point) }
    }
}

/// Where the menu bar drop zone docks the shelf.
package enum ShelfDockPlacement: String {
    case menuBar, topCenter

    /// The Dynamic Island owns the top center of the screen while it is on,
    /// so the top center placement waits until it is off.
    package static func current(in defaults: UserDefaults = .standard) -> Self {
        guard !NotchSupport.isEnabled(in: defaults),
              defaults.string(forKey: DefaultsKey.shelfDockPlacement) == Self.topCenter.rawValue
        else { return .menuBar }
        return .topCenter
    }

    /// The docked panel's frame: its top edge just below the menu bar, either
    /// centered under the icon or centered on the screen, clamped on screen.
    /// `safeTop` is the screen's `frame.maxY - safeAreaInsets.top`: with a
    /// hidden menu bar or in full screen the visible frame reaches the very top,
    /// which would put the centered badge behind the camera housing.
    package func frame(size: CGSize, visible: CGRect, safeTop: CGFloat, anchor: CGRect?) -> CGRect {
        var x = self == .topCenter
            ? visible.midX - size.width / 2
            : anchor.map { $0.midX - size.width / 2 } ?? (visible.maxX - size.width - 12)
        x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
        let top = self == .topCenter ? min(visible.maxY - 4, safeTop) : visible.maxY - 4
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}

package enum ShelfDockDragSupport {
    /// How long the pointer has to stay within the collapsed pill trigger
    /// area before expanding into the full shelf card, so a fast pass
    /// across the menu bar does not fire unintentionally.
    package static let dwell: TimeInterval = 0.15

    /// Margin around the collapsed pill and menu bar anchor that counts
    /// as aiming for the docked shelf.
    package static let triggerMargin: CGFloat = 16

    /// Margin around the expanded card to keep it open while aiming for
    /// tiles or drop targets without jitter.
    package static let retreatMargin: CGFloat = 32

    /// The hit target zone while the docked shelf is collapsed. Uses the
    /// pill frame when available, expanded by triggerMargin and unioned with
    /// the status item anchor in the menu bar.
    package static func triggerFrame(pillFrame: CGRect?,
                             anchorFrame: CGRect?,
                             screenFrame: CGRect?) -> CGRect? {
        if let pillFrame, pillFrame.width > 0, pillFrame.height > 0 {
            let padded = pillFrame.insetBy(dx: -triggerMargin, dy: -triggerMargin)
            if let anchorFrame, anchorFrame.width > 0, anchorFrame.height > 0 {
                return padded.union(anchorFrame.insetBy(dx: -triggerMargin, dy: 0))
            }
            return padded
        }
        if let anchorFrame, anchorFrame.width > 0, anchorFrame.height > 0 {
            let fallbackHeight: CGFloat = 32
            let pillY = anchorFrame.minY - 4 - fallbackHeight
            let estimatedPill = CGRect(x: anchorFrame.midX - 36,
                                       y: pillY,
                                       width: 72,
                                       height: fallbackHeight)
            return estimatedPill.insetBy(dx: -triggerMargin, dy: -triggerMargin).union(anchorFrame)
        }
        return nil
    }

    /// Whether the pointer is inside the trigger zone (when collapsed)
    /// or inside the retreat zone (when expanded).
    package static func isPointNearDock(point: CGPoint,
                                isProximate: Bool,
                                panelFrame: CGRect?,
                                anchorFrame: CGRect?,
                                screenFrame: CGRect?) -> Bool {
        if isProximate, let panelFrame, panelFrame.width > 0, panelFrame.height > 0 {
            return panelFrame.insetBy(dx: -retreatMargin, dy: -retreatMargin).contains(point)
        }
        guard let target = triggerFrame(pillFrame: panelFrame,
                                       anchorFrame: anchorFrame,
                                       screenFrame: screenFrame) else {
            return false
        }
        return target.contains(point)
    }

    /// Whether a dwell that began at `since` has lasted long enough to count
    /// as aiming to open the docked card.
    package static func hasDwelled(since: TimeInterval, now: TimeInterval, required: TimeInterval = dwell) -> Bool {
        now - since >= required
    }
}

/// Persisted form of one shelf item, so the shelf survives relaunches (and app
/// updates, which relaunch the app). Payloads and titles are stored; icons and
/// image flags are rebuilt from the payload at load.
package struct ShelfPersistedItem: Codable, Equatable {
    package enum Kind: String, Codable {
        case file, text, link, batch
    }

    package let id: UUID
    package let kind: Kind
    package let title: String
    package var text: String?
    package var url: String?
    package var path: String?
    /// Lets a file item find its payload again after a move or rename. The
    /// field is optional on purpose: stores written before it decode fine,
    /// and older app versions simply ignore it.
    package var bookmark: Data?
    package var children: [ShelfPersistedItem]?
    /// Kept after a drag-out and a Clear all. Nil rather than false when
    /// unpinned, so the common case adds nothing to the saved blob.
    package var pinned: Bool?

    package init(id: UUID,
         kind: Kind,
         title: String,
         text: String? = nil,
         url: String? = nil,
         path: String? = nil,
         bookmark: Data? = nil,
         children: [ShelfPersistedItem]? = nil,
         pinned: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.url = url
        self.path = path
        self.bookmark = bookmark
        self.children = children
        self.pinned = pinned == true ? true : nil
    }
}

// The custom decoder lives in an extension so the memberwise initializer
// stays synthesized. It tolerates blobs written by other versions: absent
// fields fall back to their defaults, and an unknown kind fails just this
// item, which the lossy array decode in `ShelfPersistenceSupport.load` then
// drops instead of losing the whole shelf.
extension ShelfPersistedItem {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, text, url, path, bookmark, children, pinned
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try container.decode(Kind.self, forKey: .kind),
                  title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
                  text: try container.decodeIfPresent(String.self, forKey: .text),
                  url: try container.decodeIfPresent(String.self, forKey: .url),
                  path: try container.decodeIfPresent(String.self, forKey: .path),
                  bookmark: try container.decodeIfPresent(Data.self, forKey: .bookmark),
                  children: try container.decodeIfPresent([FailableShelfPersistedItem].self, forKey: .children)?
                      .compactMap(\.value),
                  pinned: try container.decodeIfPresent(Bool.self, forKey: .pinned))
    }
}

private struct FailableShelfPersistedItem: Decodable {
    let value: ShelfPersistedItem?

    init(from decoder: Decoder) throws {
        value = try? ShelfPersistedItem(from: decoder)
    }
}

/// What the saved shelf blob turned out to be. The outcomes are kept apart
/// because they need opposite handling, and collapsing them into a plain
/// item list is what lets a decode failure pass for an empty shelf: writing
/// that empty list back and sweeping the payload files behind it turns one
/// bad blob into permanent loss.
package enum ShelfStoreLoad: Equatable {
    /// No blob yet (first launch), or a blob that decoded whole — possibly to
    /// an empty list, which is a shelf the user emptied.
    case items([ShelfPersistedItem])
    /// A blob that decoded, but with entries this build could not read: an
    /// unknown kind written by a newer build, at the top level or inside a
    /// batch. Those entries still own payload files in the shelf's own
    /// directory, and the blob still points at them, so their files must
    /// survive to the launch that can read the store again.
    case partial([ShelfPersistedItem])
    /// A blob that is not a shelf list at all. Leave it, and the payload
    /// files it still references, alone until the next launch.
    case unreadable
}

package enum ShelfPersistenceSupport {
    /// Ceilings so a stale or hand-edited blob cannot balloon startup: the
    /// shelf is a hand-curated surface, not an archive.
    package static let maxLeaves = 200
    package static let maxTextLength = 200_000
    package static let maxDepth = 4

    /// The only way into the saved shelf. Callers get a case they have to
    /// answer for, so "the blob did not decode" cannot quietly become "the
    /// shelf is empty" the way decoding the array outright does. Entries are
    /// lossy on their own: one with an unknown kind or a missing required
    /// field drops itself instead of taking the rest with it, and a list that
    /// lost an entry that way comes back as `.partial`, not `.items`.
    package static func load(_ data: Data?) -> ShelfStoreLoad {
        guard let data else { return .items([]) }
        guard let decoded = try? JSONDecoder().decode([FailableShelfPersistedItem].self,
                                                      from: data) else { return .unreadable }
        let items = decoded.compactMap(\.value)
        // A stored list where nothing survived is a shelf this build cannot
        // read (a downgrade past a format change), not one the user emptied.
        if !decoded.isEmpty, items.isEmpty { return .unreadable }
        // Counted rather than read off `decoded.count`: an entry can also drop
        // itself inside a batch, and its payload file is as real as a top-level
        // one's. The blob kept still points at every dropped entry's file.
        let stored = storedEntryCount(try? JSONSerialization.jsonObject(with: data))
        return stored == readEntryCount(items) ? .items(items) : .partial(items)
    }

    /// Entries the blob describes at every depth, readable or not.
    private static func storedEntryCount(_ json: Any?) -> Int {
        guard let entries = json as? [Any] else { return 0 }
        return entries.reduce(0) { total, entry in
            total + 1 + storedEntryCount((entry as? [String: Any])?["children"])
        }
    }

    /// Entries this build read at every depth.
    private static func readEntryCount(_ items: [ShelfPersistedItem]) -> Int {
        items.reduce(0) { $0 + 1 + readEntryCount($1.children ?? []) }
    }

    package static func boundedLiveText(_ text: String) -> String? {
        let bounded = String(text.prefix(maxTextLength))
        guard !bounded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return bounded
    }

    package static func canAdd(existingLeaves: Int, newLeaves: Int) -> Bool {
        existingLeaves >= 0 && newLeaves > 0 && existingLeaves <= maxLeaves - newLeaves
    }

    /// A stored attachment can have its own directory to preserve its name.
    /// Startup cleanup must keep that directory while a descendant is referenced.
    package static func containsKeptFile(under path: String, keptPaths: Set<String>) -> Bool {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        return keptPaths.contains(path) || keptPaths.contains { $0.hasPrefix(path + "/") }
    }

    package static func discardablePayloadPaths(candidatePaths: [String],
                                        referencedPaths: Set<String>) -> Set<String> {
        Set(candidatePaths).subtracting(referencedPaths)
    }

    package static func needsPersistAfterRestore(restoredIsEmpty: Bool, liveItemCount: Int) -> Bool {
        restoredIsEmpty || liveItemCount > 0
    }

    /// Drops entries that can no longer be honored (missing files, empty text,
    /// invalid links) and mirrors the live shelf's batch rules: an emptied
    /// batch disappears and a single-child batch collapses to its child, the
    /// same way removing items from a live batch behaves.
    ///
    /// `fileExists` decides whether a file item survives. Callers must answer
    /// true for files on volumes that are merely NOT MOUNTED right now (see
    /// unmountedVolumeRoot): the app can launch at login before an external
    /// or network drive appears, and dropping those items would lose them
    /// permanently the moment the pruned list is saved back.
    ///
    /// `resolveBookmark` gives a dead path one chance to heal: a file moved
    /// or renamed behind the app's back is found again through its bookmark,
    /// and the entry keeps living under its new path and name.
    package static func sanitized(_ items: [ShelfPersistedItem],
                          fileExists: (String) -> Bool,
                          resolveBookmark: (Data) -> String? = { _ in nil }) -> [ShelfPersistedItem] {
        var remainingLeaves = maxLeaves
        return sanitized(items, depth: 0, remainingLeaves: &remainingLeaves,
                         fileExists: fileExists, resolveBookmark: resolveBookmark)
    }

    /// For a path under /Volumes, the volume root directory that must exist
    /// for the file's absence to be meaningful; nil for boot-volume paths.
    package static func unmountedVolumeRoot(of path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard components.count > 2, components[0] == "/", components[1] == "Volumes" else {
            return nil
        }
        return "/Volumes/" + components[2]
    }

    private static func sanitized(_ items: [ShelfPersistedItem],
                                  depth: Int,
                                  remainingLeaves: inout Int,
                                  fileExists: (String) -> Bool,
                                  resolveBookmark: (Data) -> String?) -> [ShelfPersistedItem] {
        guard depth < maxDepth else { return [] }
        var result: [ShelfPersistedItem] = []
        for item in items {
            guard remainingLeaves > 0 else { break }
            switch item.kind {
            case .file:
                guard let path = item.path, !path.isEmpty else { continue }
                var keptPath = path
                var keptTitle = item.title
                if !fileExists(path) {
                    guard let bookmark = item.bookmark,
                          let healed = resolveBookmark(bookmark),
                          fileExists(healed) else { continue }
                    keptPath = healed
                    keptTitle = (healed as NSString).lastPathComponent
                }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .file, title: keptTitle,
                                                 path: keptPath, bookmark: item.bookmark,
                                                 pinned: item.pinned))
            case .text:
                guard let text = item.text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .text, title: item.title,
                                                 text: String(text.prefix(maxTextLength)),
                                                 pinned: item.pinned))
            case .link:
                guard let raw = item.url, let url = URL(string: raw),
                      url.scheme != nil, !url.isFileURL else { continue }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .link, title: item.title, url: raw,
                                                 pinned: item.pinned))
            case .batch:
                let children = sanitized(item.children ?? [], depth: depth + 1,
                                         remainingLeaves: &remainingLeaves,
                                         fileExists: fileExists, resolveBookmark: resolveBookmark)
                if children.isEmpty { continue }
                if children.count == 1 {
                    // The survivor inherits the pile's pin, as it does live.
                    var survivor = children[0]
                    if item.pinned == true { survivor.pinned = true }
                    result.append(survivor)
                    continue
                }
                result.append(ShelfPersistedItem(id: item.id, kind: .batch, title: item.title,
                                                 children: children, pinned: item.pinned))
            }
        }
        return result
    }
}
