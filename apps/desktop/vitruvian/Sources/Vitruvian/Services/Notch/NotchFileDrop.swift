// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// Files dragged onto the island. A drop the media tools can take offers two
/// destinations, the shelf and the tools, and the pointer picks one; any
/// other drop goes to the shelf.
package final class NotchFileDrop {
    /// Where a drop can go. The app passes `.system(shelfAccept:)`.
    package struct Environment {
        /// The media tools can take what the pasteboard holds.
        package var offersMedia: (NSPasteboard) -> Bool
        /// The media tools can take a drop now.
        package var mediaAccepts: () -> Bool
        package var openMedia: (NSPasteboard) -> Bool
        package var hideMedia: () -> Void
        package var shelfAccept: (NSPasteboard) -> Bool

        package init(offersMedia: @escaping (NSPasteboard) -> Bool, mediaAccepts: @escaping () -> Bool,
                     openMedia: @escaping (NSPasteboard) -> Bool, hideMedia: @escaping () -> Void,
                     shelfAccept: @escaping (NSPasteboard) -> Bool) {
            self.offersMedia = offersMedia
            self.mediaAccepts = mediaAccepts
            self.openMedia = openMedia
            self.hideMedia = hideMedia
            self.shelfAccept = shelfAccept
        }

        package static func system(shelfAccept: @escaping (NSPasteboard) -> Bool) -> Environment {
            Environment(offersMedia: { NotchFileToolsService.shared.mediaDropContent(for: $0) != nil },
                        mediaAccepts: { NotchFileToolsService.shared.canAcceptMediaDrop },
                        openMedia: { NotchFileToolsService.shared.openMediaDrop($0) },
                        hideMedia: { NotchFileToolsService.shared.hideMedia() },
                        shelfAccept: shelfAccept)
        }
    }

    /// The island's side.
    package struct Island {
        /// The island takes files now (`NotchService.canAcceptFileDrop`).
        package var canAccept: () -> Bool
        package var acceptsUserInteraction: () -> Bool
        /// Where on the open island the media tools take the drop.
        package var mediaArea: () -> CGRect
        /// Runs before the destinations change, so the views showing them redraw.
        package var willChange: () -> Void
        /// Opens the island on its files, taking focus or not.
        package var openFiles: (_ takeFocus: Bool) -> Void
        package var refreshPresentation: () -> Void
        /// A drop landed: the island stops holding the drag.
        package var landed: () -> Void

        package init(canAccept: @escaping () -> Bool, acceptsUserInteraction: @escaping () -> Bool,
                     mediaArea: @escaping () -> CGRect, willChange: @escaping () -> Void,
                     openFiles: @escaping (_ takeFocus: Bool) -> Void, refreshPresentation: @escaping () -> Void,
                     landed: @escaping () -> Void) {
            self.canAccept = canAccept
            self.acceptsUserInteraction = acceptsUserInteraction
            self.mediaArea = mediaArea
            self.willChange = willChange
            self.openFiles = openFiles
            self.refreshPresentation = refreshPresentation
            self.landed = landed
        }
    }

    private let environment: Environment
    private let island: Island

    /// The drag offers the shelf and the media tools as destinations.
    package private(set) var choosingDestination = false {
        willSet { island.willChange() }
    }
    /// The pointer is over the media tools' destination.
    package private(set) var targetsMedia = false {
        willSet { island.willChange() }
    }

    package init(environment: Environment, island: Island) {
        self.environment = environment
        self.island = island
    }

    /// A drag entered the island: it opens on its files, offering the media
    /// tools when they can take what is dragged.
    package func begin(_ pasteboard: NSPasteboard) {
        guard island.canAccept() else { return }
        choosingDestination = environment.offersMedia(pasteboard)
        targetsMedia = false
        island.openFiles(false)
    }

    /// The drag moved to `point`; returns whether a drop there would land.
    @discardableResult
    package func update(at point: CGPoint) -> Bool {
        let targeted = choosingDestination && island.mediaArea().contains(point)
        if targetsMedia != targeted { targetsMedia = targeted }
        return !targeted || environment.mediaAccepts()
    }

    /// The drag left or ended.
    package func end() {
        let changed = choosingDestination
        if changed { choosingDestination = false }
        if targetsMedia { targetsMedia = false }
        if changed, island.acceptsUserInteraction() { island.refreshPresentation() }
    }

    /// Delivers the drop to the destination the pointer chose.
    package func accept(_ pasteboard: NSPasteboard) -> Bool {
        defer { end() }
        guard island.canAccept() else { return false }
        let optimize = choosingDestination && targetsMedia
        let accepted = optimize ? environment.openMedia(pasteboard) : environment.shelfAccept(pasteboard)
        if accepted {
            island.landed()
            if !optimize { environment.hideMedia() }
            island.openFiles(true)
        }
        return accepted
    }
}
