// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production lookups of the display under the pointer run against
/// stand-in displays, so the edges between displays are checked without a
/// second monitor. Nothing is captured, moved, warped or shown.
enum PointerDisplayLookupContract {
    static func screen(_ displayID: CGDirectDisplayID, _ frame: NSRect, scale: CGFloat) -> ScreenGeometry {
        ScreenGeometry(displayID: displayID, frame: frame,
                       visibleFrame: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - 25),
                       scale: scale)
    }

    /// The display each production lookup settles on for one pointer position.
    static func displays(under pointer: NSPoint, screens: [ScreenGeometry], main: ScreenGeometry,
                         topology: SpaceWindowBridge.Topology) -> [(String, CGDirectDisplayID?)] {
        func display(holding rect: CGRect) -> CGDirectDisplayID? {
            screens.first { $0.visibleFrame.contains(rect) }?.displayID
        }
        let hud = CGSize(width: 300, height: 48)
        let window = CGSize(width: 400, height: 300)
        let dropped = DockPreviewSupport.dropOrigin(pointer: pointer, windowSize: window, screens: screens,
                                                    fallback: main)
        return [
            ("a full-display capture", ScreenGeometry.under(pointer, among: screens, fallback: main)?.displayID),
            ("the Space a dropped window joins",
             SpaceWindowBridge.visibleSpace(near: pointer, in: topology, screens: screens, main: main)
                .map { CGDirectDisplayID($0 / 10) }),
            ("the directional layout indicator",
             display(holding: WindowDirectionalIndicator.frame(pointer: pointer, screens: screens, main: main))),
            ("the quit confirmation", QuitProtectionSupport.panelOrigin(size: hud, preferred: nil, pointer: pointer,
                                                                         screens: screens, main: main)
                .flatMap { display(holding: CGRect(origin: $0, size: hud)) }),
            ("a full-display capture from the capture overlay",
             ScreenGeometry.under(pointer, among: screens, fallback: screens.first)?.displayID),
            ("a window dropped from a Dock preview",
             display(holding: CGRect(x: dropped.x, y: dropped.y - window.height, width: window.width, height: window.height))),
        ]
    }

    static func run(_ suite: TestSuite) {
        // A Retina primary with a display on its right and one stacked above.
        // AppKit reports a display's top row at frame.maxY and its bottom row
        // just above frame.minY. The main display is the primary.
        let primary = screen(1, NSRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let right = screen(2, NSRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1)
        let above = screen(3, NSRect(x: 0, y: 900, width: 1440, height: 900), scale: 1)
        let screens = [primary, right, above]
        let topology = SpaceWindowBridge.Topology(displays: screens.map {
            .init(displayID: $0.displayID, spaces: [], fullscreenSpaces: [],
                  currentSpace: UInt64($0.displayID) * 10)
        })
        let edges: [(NSPoint, ScreenGeometry, String)] = [
            (NSPoint(x: 2000, y: 1080), right, "a pointer on the top row of a secondary display"),
            (NSPoint(x: 700, y: 900), primary, "a pointer on the top row of a display with another above it"),
            (NSPoint(x: 700, y: 1800), above, "a pointer on the top row of the upper display"),
            (NSPoint(x: 700, y: 901), above, "a pointer on the bottom row of the upper display"),
            (NSPoint(x: 700, y: 1), primary, "a pointer on the bottom row of a display"),
            (NSPoint(x: 1440, y: 500), right, "a pointer on the first column of a display on the right"),
            (NSPoint(x: 2000, y: 500), right, "a pointer inside a display"),
        ]
        let outside = (NSPoint(x: 5000, y: 5000), primary, "a pointer outside every display")
        for (pointer, expected, place) in edges + [outside] {
            for (lookup, found) in displays(under: pointer, screens: screens, main: primary, topology: topology) {
                suite.expect(found == expected.displayID,
                             "\(lookup) follows \(place) to display \(expected.displayID), found \(found.map(String.init) ?? "none")")
            }
        }
        // A display the Space topology does not list, and none at all.
        let unlisted = SpaceWindowBridge.Topology(displays: [.init(displayID: 9, spaces: [], fullscreenSpaces: [],
                                                                   currentSpace: 90)])
        suite.expect(SpaceWindowBridge.visibleSpace(near: NSPoint(x: 700, y: 1), in: unlisted, screens: screens,
                                                    main: primary) == 90
                     && QuitProtectionSupport.panelOrigin(size: .zero, preferred: nil, pointer: .zero, screens: [],
                                                          main: nil) == nil,
                     "a display the topology misses falls back to its first, and no display places nothing")
        suite.expect(SpaceWindowBridge.visibleSpace(near: outside.0, in: topology, screens: screens, main: right) == 20,
                     "a pointer outside every display follows the main display's Space")
        let docked = ScreenGeometry(displayID: 4, frame: NSRect(x: 0, y: 0, width: 1000, height: 800),
                                    visibleFrame: NSRect(x: 0, y: 70, width: 1000, height: 705), scale: 1)
        suite.expect(QuitProtectionSupport.panelOrigin(size: CGSize(width: 300, height: 48), preferred: docked,
                                                       pointer: .zero, screens: screens, main: primary) == CGPoint(x: 350, y: 88)
                     && QuitProtectionSupport.panelOrigin(size: CGSize(width: 300, height: 48), preferred: nil,
                                                          pointer: outside.0, screens: screens, main: nil) == CGPoint(x: 570, y: 18),
                     "the quit confirmation clears the Dock, and without a main display uses the first")
        suite.expect(QuitProtectionSupport.panelOrigin(size: CGSize(width: 301, height: 48), preferred: right,
                                                       pointer: NSPoint(x: 700, y: 1), screens: screens,
                                                       main: primary) == CGPoint(x: 2250, y: 18),
                     "the quit confirmation goes to the display it was asked for, rounded to whole points")
        let corner = WindowDirectionalIndicator.frame(pointer: NSPoint(x: 1435, y: 5), screens: screens, main: primary)
        suite.expect(corner == CGRect(x: 1440 - 8 - 180, y: 8, width: 180, height: 180),
                     "the directional indicator stays 8 points inside its display's corner")
        // The loupe's arrow keys step by one device pixel of the display the
        // pointer is on, and never jump to another display at its top edge.
        for (pointer, expected, place) in edges {
            let moved = ScreenshotSupport.capturePointerNudge(keyCode: kVK_RightArrow, fast: false, from: pointer,
                                                              screens: screens, fallback: primary)
            let step = CGPoint(x: pointer.x + 1 / expected.scale, y: pointer.y)
            suite.expect(moved == step,
                         "an arrow key moves \(place) by one pixel of its own display, found \(moved.map { "\($0)" } ?? "none")")
        }
        let keys: [(Int, Bool, CGPoint)] = [(kVK_LeftArrow, false, CGPoint(x: 1999, y: 500)),
                                            (kVK_UpArrow, false, CGPoint(x: 2000, y: 501)),
                                            (kVK_DownArrow, true, CGPoint(x: 2000, y: 490))]
        for (key, fast, expected) in keys {
            suite.expect(ScreenshotSupport.capturePointerNudge(keyCode: key, fast: fast, from: NSPoint(x: 2000, y: 500),
                                                               screens: screens, fallback: primary) == expected,
                         "each arrow moves the pointer its own way, ten pixels with Shift")
        }
        suite.expect(ScreenshotSupport.capturePointerNudge(keyCode: kVK_RightArrow, fast: false,
                                                           from: NSPoint(x: 1439.5, y: 500), screens: screens,
                                                           fallback: primary) == CGPoint(x: 1440, y: 500)
                     && ScreenshotSupport.capturePointerNudge(keyCode: kVK_RightArrow, fast: false,
                                                              from: outside.0, screens: screens,
                                                              fallback: primary) == CGPoint(x: 1439.5, y: 900),
                     "the pointer crosses onto the next display, and one on no display stops on the fallback's edge")
        suite.expect(ScreenshotSupport.capturePointerNudge(keyCode: kVK_Space, fast: false, from: .zero,
                                                           screens: screens, fallback: primary) == nil
                     && ScreenshotSupport.capturePointerNudge(keyCode: kVK_RightArrow, fast: false, from: .zero,
                                                              screens: [], fallback: nil) == nil,
                     "another key, or no display, moves nothing")
        // Past the outer edge of the desktop the pointer stops on the display's
        // last row or column, where the overlay under the pointer still finds it.
        let stops: [(NSPoint, Int, Bool, NSPoint, ScreenGeometry, String)] = [
            (NSPoint(x: 2000, y: 1), kVK_DownArrow, false, NSPoint(x: 2000, y: 1), right, "the bottom row of a display"),
            (NSPoint(x: 700, y: 0.5), kVK_DownArrow, false, NSPoint(x: 700, y: 0.5), primary, "the bottom row of a Retina display"),
            (NSPoint(x: 2000, y: 5), kVK_DownArrow, true, NSPoint(x: 2000, y: 1), right, "the bottom of a display with Shift held"),
            (NSPoint(x: 3359, y: 500), kVK_RightArrow, false, NSPoint(x: 3359, y: 500), right, "the last column of a display"),
            (NSPoint(x: 1, y: 500), kVK_LeftArrow, true, NSPoint(x: 0, y: 500), primary, "the first column of a display"),
            (NSPoint(x: 2000, y: 1078), kVK_UpArrow, true, NSPoint(x: 2000, y: 1080), right, "the top row of a display"),
        ]
        for (pointer, key, fast, stop, expected, place) in stops {
            let moved = ScreenshotSupport.capturePointerNudge(keyCode: key, fast: fast, from: pointer,
                                                              screens: screens, fallback: primary)
            let found = moved.flatMap { ScreenGeometry.under($0, among: screens, fallback: screens.first) }?.frame
            suite.expect(moved == stop && found == expected.frame,
                         "an arrow key past \(place) stops the pointer on that display, found \(moved.map { "\($0)" } ?? "none") on \(found.map { "\($0)" } ?? "none")")
        }
    }
}
