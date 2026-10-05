// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production preview's hover handling and dismissal run with a
/// controlled clock. Pointer crossings are supplied explicitly; the preview
/// is never shown, so no native UI is exercised.
enum ScreenshotPreviewHoverTests {
    typealias Scheduler = NotchScreenRefreshContract.Scheduler
    typealias Action = ScreenshotQuickPreviewController.Action

    /// A preview that is never shown, on `clock`, that records being closed.
    final class Preview {
        var closed = false
        var action: (Action) -> Set<Action> = { [$0] }
        private(set) var controller: ScreenshotQuickPreviewController!

        init(clock: Scheduler, dismissInterval: TimeInterval? = 12) {
            let pixels = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
            controller = ScreenshotQuickPreviewController(
                capture: .init(image: pixels, scale: 1, anchorRect: .zero),
                strings: .enUS, defaultAction: .none, completedActions: [],
                dismissInterval: dismissInterval,
                action: { [unowned self] in self.action($0) },
                share: { _, _ in }, shareFile: { nil },
                onClose: { [unowned self] in self.closed = true },
                scheduler: .init(async: { work in clock.async { work() } },
                                 after: { delay, work in
                                     clock.asyncAfter(deadline: .init(seconds: clock.now + delay), execute: work)
                                 }))
        }
    }

    static func run(_ suite: TestSuite) {
        var clock = Scheduler()
        let editorPreview = Preview(clock: clock)
        var editorOpened = false
        editorPreview.action = { action in
            suite.expect(editorPreview.closed, "Edit releases preview focus before opening the editor")
            editorOpened = true
            return [action]
        }
        editorPreview.controller.perform(.edit)
        suite.expect(editorPreview.closed && !editorOpened,
                     "Edit dismisses immediately and defers window creation beyond the button update")
        editorPreview.controller.perform(.edit)
        clock.advance(0)
        suite.expect(editorOpened && clock.pending == 0,
                     "Edit opens exactly once on the next main-queue turn")
        let failedCopy = Preview(clock: Scheduler())
        failedCopy.action = { _ in [] }
        failedCopy.controller.perform(.copy)
        suite.expect(!failedCopy.closed, "failed Copy still leaves the preview available for retry")

        for duration in [3.0, 12.0] {
            clock = Scheduler()
            let preview = Preview(clock: clock, dismissInterval: duration)
            let controller = preview.controller!
            func imageHover(_ inside: Bool, embedded: Bool) {
                ScreenshotQuickPreviewController.forwardImageHover(inside, embedded: embedded,
                                                                   to: controller.hoverChanged)
            }
            controller.scheduleAutoDismiss()
            controller.hoverChanged(true) // Enter the island through the header.
            clock.advance(duration)
            suite.expect(!preview.closed, "entering the capture header cancels automatic dismissal")

            for _ in 0..<2 {
                imageHover(true, embedded: true) // Header to image.
                imageHover(false, embedded: true) // Image to header, still in the island.
                clock.advance(duration)
                suite.expect(controller.pointerInside && !preview.closed && clock.pending == 0,
                             "moving between the image and header actions keeps the embedded preview open")
            }

            controller.hoverChanged(false) // Leave the whole island.
            clock.advance(duration - 0.5)
            suite.expect(!preview.closed, "leaving the island keeps the configured dismissal delay")
            controller.hoverChanged(true) // Return before the deadline.
            clock.advance(duration)
            suite.expect(!preview.closed, "returning to the header cancels an outstanding dismissal")
            controller.hoverChanged(false)
            clock.advance(duration)
            suite.expect(preview.closed, "leaving the island still dismisses an unused capture")

            // Disabling the island rebuilds the preview as a floating view.
            clock = Scheduler()
            let floatingPreview = Preview(clock: clock, dismissInterval: duration)
            let floatingController = floatingPreview.controller!
            floatingController.scheduleAutoDismiss()
            ScreenshotQuickPreviewController.forwardImageHover(true, embedded: false,
                                                               to: floatingController.hoverChanged)
            clock.advance(duration)
            suite.expect(floatingController.pointerInside && !floatingPreview.closed,
                         "the floating preview still cancels dismissal while hovered")
            ScreenshotQuickPreviewController.forwardImageHover(false, embedded: false,
                                                               to: floatingController.hoverChanged)
            clock.advance(duration - 0.5)
            suite.expect(!floatingPreview.closed, "the floating preview retains its dismissal delay")
            clock.advance(0.5)
            suite.expect(floatingPreview.closed, "leaving the floating preview still dismisses it")

            // The system share sheet opens outside the preview, so the pointer
            // leaves it while a target is being picked.
            clock = Scheduler()
            let sharingPreview = Preview(clock: clock, dismissInterval: duration)
            let sharingController = sharingPreview.controller!
            sharingController.systemSharing = true
            sharingController.hoverChanged(true)
            sharingController.hoverChanged(false)
            clock.advance(duration)
            suite.expect(!sharingPreview.closed && clock.pending == 0,
                         "an open share sheet keeps the preview from dismissing")
            sharingController.systemSharing = false
            sharingController.scheduleAutoDismiss()
            clock.advance(duration)
            suite.expect(sharingPreview.closed, "a cancelled share sheet resumes the dismissal delay")
        }

        clock = Scheduler()
        let persistentPreview = Preview(clock: clock, dismissInterval: nil)
        persistentPreview.controller.scheduleAutoDismiss()
        clock.advance(60)
        suite.expect(!persistentPreview.closed && clock.pending == 0,
                     "a persistent confirmation preview does not schedule automatic dismissal")
    }
}

extension NotchScreenRefreshContract.Scheduler {
    func async(execute work: @escaping () -> Void) {
        asyncAfter(deadline: .init(seconds: now), execute: DispatchWorkItem(block: work))
    }
}
