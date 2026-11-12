// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production checks of whether the pointer is on a display run against
/// stand-in display frames, so the edges between displays are covered without
/// a second monitor. Nothing is warped, pressed or shown.
enum PointerOnDisplayContract {
    struct Screen {
        let displayID: CGDirectDisplayID
        let frame: NSRect
        init(_ displayID: CGDirectDisplayID, _ frame: NSRect) {
            self.displayID = displayID
            self.frame = frame
        }
    }

    static func run(_ suite: TestSuite) {
        // A display on the right of the primary and one stacked above it.
        // AppKit reports a display's top row at frame.maxY and its bottom row
        // just above frame.minY. The main display is the primary.
        let primary = Screen(1, NSRect(x: 0, y: 0, width: 1440, height: 900))
        let right = Screen(2, NSRect(x: 1440, y: 0, width: 1920, height: 1080))
        let above = Screen(3, NSRect(x: 0, y: 900, width: 1440, height: 900))
        let screens = [primary, right, above]
        /// The display as CoreGraphics places it, measured down from the top
        /// of the primary display.
        func bounds(of screen: Screen) -> CGRect {
            CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        let edges: [(NSPoint, Screen, String)] = [
            (NSPoint(x: 2000, y: 1080), right, "a pointer on the top row of a secondary display"),
            (NSPoint(x: 700, y: 900), primary, "a pointer on the top row of a display with another above it"),
            (NSPoint(x: 700, y: 1800), above, "a pointer on the top row of the upper display"),
            (NSPoint(x: 700, y: 901), above, "a pointer on the bottom row of the upper display"),
            (NSPoint(x: 700, y: 1), primary, "a pointer on the bottom row of a display"),
            (NSPoint(x: 1440, y: 500), right, "a pointer on the first column of a display on the right"),
            (NSPoint(x: 2000, y: 500), right, "a pointer inside a display"),
        ]
        for (pointer, under, place) in edges {
            // The Spaces shortcut acts on the display under the pointer, so a
            // hop brings the pointer to the window's display only from another.
            for target in screens {
                let warp = SpaceHopSupport.warpTarget(pointer: pointer, displayFrame: target.frame,
                                                      displayBounds: bounds(of: target))
                let center = CGPoint(x: bounds(of: target).midX, y: bounds(of: target).midY)
                let expected = target.displayID == under.displayID ? nil : center
                let behavior = expected == nil
                    ? "leaves \(place) where it is when the window is on that display"
                    : "brings \(place) to the window's display \(target.displayID)"
                suite.expect(warp == expected, "a Space hop \(behavior), found \(String(describing: warp))")
            }
            // The capture guide follows the pointer to its display and no other.
            let shown = screens.filter {
                ScreenshotSupport.captureGuideIsVisible(pointer: pointer, displayFrame: $0.frame,
                                                        selectionInProgress: false, capturePending: false)
            }.map(\.displayID)
            suite.expect(shown == [under.displayID],
                         "the capture guide shows only on display \(under.displayID) for \(place), found \(shown)")
            suite.expect(!ScreenshotSupport.captureGuideIsVisible(pointer: pointer, displayFrame: under.frame,
                                                                  selectionInProgress: true, capturePending: false)
                         && !ScreenshotSupport.captureGuideIsVisible(pointer: pointer, displayFrame: under.frame,
                                                                     selectionInProgress: false, capturePending: true),
                         "the capture guide hides during a selection or a pending capture for \(place)")
        }
        suite.expect(SpaceHopSupport.warpTarget(pointer: .zero, displayFrame: nil, displayBounds: bounds(of: right)) == nil
                     && SpaceHopSupport.warpTarget(pointer: .zero, displayFrame: right.frame,
                                                   displayBounds: bounds(of: right)) == CGPoint(x: 2400, y: 360),
                     "a window's display without a frame is not warped to, and its middle is measured from the top")
        // With 64-point icons the Dock's strip is 160 points deep, measured
        // from the edge of the display the pointer is on.
        let dock: [(NSPoint, DockPreviewOrientation, Bool, String)] = [
            (NSPoint(x: 700, y: 900), .bottom, false, "a pointer on the top row of a display with another above it"),
            (NSPoint(x: 2000, y: 1080), .right, false, "a pointer on the top row of a display on the right"),
            (NSPoint(x: 3300, y: 1080), .right, true, "a pointer on the top row of a display on the right, by its right edge"),
            (NSPoint(x: 700, y: 901), .bottom, true, "a pointer on the bottom row of the upper display"),
            (NSPoint(x: 700, y: 1), .bottom, true, "a pointer on the bottom row of a display"),
            (NSPoint(x: 700, y: 160), .bottom, true, "a pointer on the strip's own top row"),
            (NSPoint(x: 700, y: 161), .bottom, false, "a pointer just above the strip"),
            (NSPoint(x: 1440, y: 500), .left, true, "a pointer on the first column of a display on the right"),
            (NSPoint(x: 5000, y: 100), .bottom, true, "a pointer on no display, inside the main display's strip"),
            (NSPoint(x: 5000, y: 400), .bottom, false, "a pointer on no display, above the main display's strip"),
        ]
        func preferences(_ orientation: DockPreviewOrientation) -> DockPreviewPreferences {
            DockPreviewPreferences(orientation: orientation, autohide: false, tileSize: 64,
                                   magnification: false, magnifiedTileSize: 128)
        }
        for (pointer, orientation, near, place) in dock {
            let found = DockPreviewSupport.isNearDock(pointer, screenFrames: screens.map(\.frame),
                                                      mainFrame: primary.frame, preferences: preferences(orientation))
            suite.expect(found == near,
                         "\(place) is \(near ? "inside" : "outside") the strip of a Dock on the \(orientation) edge of that display, found \(found)")
        }
        suite.expect(DockPreviewSupport.isNearDock(NSPoint(x: 700, y: 800), screenFrames: screens.map(\.frame),
                                                   mainFrame: primary.frame, preferences: nil)
                     && DockPreviewSupport.isNearDock(NSPoint(x: 700, y: 800), screenFrames: [], mainFrame: nil,
                                                      preferences: preferences(.bottom)),
                     "without the Dock's preferences or any display every point is worth the hit test")
        let magnified = DockPreviewPreferences(orientation: .bottom, autohide: false, tileSize: 64,
                                               magnification: true, magnifiedTileSize: 128)
        suite.expect(DockPreviewSupport.isNearDock(NSPoint(x: 700, y: 250), screenFrames: screens.map(\.frame),
                                                   mainFrame: primary.frame, preferences: magnified),
                     "a magnifying Dock's strip is as deep as its largest icon")
    }
}
