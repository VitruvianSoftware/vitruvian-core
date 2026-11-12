// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum NotchSectionPagingTests {
    static func run(_ suite: TestSuite) {
        suite.expect(NotchSectionPaging.rows(count: 14, columns: 4) == 4 && NotchSectionPaging.rows(count: 12, columns: 4) == 3
               && NotchSectionPaging.rows(count: 0, columns: 4) == 1 && NotchSectionPaging.rows(count: 5, columns: 0) == 5,
               "rows round the last partial row up and never vanish")
        suite.expect(NotchSectionPaging.positions(rows: 4, visible: 3) == 2 && NotchSectionPaging.positions(rows: 2, visible: 3) == 1
               && NotchSectionPaging.positions(rows: 5, visible: 1) == 5 && NotchSectionPaging.positions(rows: 4, visible: 0) == 4,
               "a gallery rests on as many rows as can lead the visible ones")
        suite.expect(NotchSectionPaging.clamped(5, rows: 4, visible: 3) == 1 && NotchSectionPaging.clamped(-1, rows: 4, visible: 3) == 0
               && NotchSectionPaging.clamped(1, rows: 4, visible: 3) == 1,
               "the first row never rests past the last position")
        suite.expect(NotchSectionPaging.revealing(row: 3, first: 0, rows: 4, visible: 3) == 1
               && NotchSectionPaging.revealing(row: 0, first: 1, rows: 4, visible: 3) == 0
               && NotchSectionPaging.revealing(row: 1, first: 0, rows: 4, visible: 3) == 0
               && NotchSectionPaging.revealing(row: 2, first: 1, rows: 4, visible: 3) == 1
               && NotchSectionPaging.revealing(row: 4, first: 0, rows: 5, visible: 1) == 4
               && NotchSectionPaging.revealing(row: 2, first: 9, rows: 4, visible: 3) == 1,
               "a highlighted row comes into view with the least movement, from a clamped start")

        var scroll = NotchSectionScroll()
        var time = 10.0
        func feed(_ y: Double, began: Bool = false, ended: Bool = false, momentum: Bool = false,
                  precise: Bool = true, phased: Bool = true, after gap: TimeInterval = 0.01) -> Int {
            time += gap
            return scroll.steps(deltaY: y, timestamp: time, precise: precise, hasPhase: phased,
                                began: began, ended: ended, momentum: momentum)
        }
        suite.expect(feed(0, began: true) == 0 && feed(-5) == 0 && feed(-10) == 0 && feed(-10) == 1,
               "a short downward movement accumulates into one row below, matching the island's gesture distance")
        suite.expect(feed(-50) == 0 && feed(-50) == 1,
               "further rows in the same drag follow the row pitch rather than the short first step")
        suite.expect(feed(-300) == 3, "a long continuous drag steps several rows at once")
        suite.expect(feed(0, ended: true) == 0 && feed(-400, momentum: true) == 0 && feed(-400, momentum: true) == 0,
               "momentum after lifting the fingers never moves another row")
        suite.expect(feed(-30, began: true) == 1 && feed(30) == -1,
               "turning back answers with the short first step again, revealing the row above")
        for sign in [-1, 1] {
            for (distance, rows) in [(23.0, 0), (24.0, 1), (25.0, 1), (118.0, 2)] {
                suite.expect(feed(Double(sign) * distance, began: true) == -sign * rows
                       && feed(0) == 0 && feed(Double(-sign) * 24) == sign,
                       "reversing resets the first step in either direction, even with zero distance left after \(distance) points")
            }
            suite.expect(feed(Double(sign) * 24, began: true) == -sign
                   && feed(0) == 0 && feed(Double(sign) * 24) == 0
                   && feed(Double(sign) * 70) == -sign,
                   "zero remainder and resting fingers preserve the longer pitch when continuing in the same direction")
        }
        suite.expect(feed(0, ended: true) == 0 && feed(-20, began: true) == 0 && feed(0) == 0 && feed(-3) == 0 && feed(-2) == 1,
               "resting fingers and sideways events keep the accumulated distance")
        suite.expect(feed(-1, precise: false, phased: false) == 1 && feed(3, precise: false, phased: false) == -1
               && feed(0, precise: false, phased: false) == 0,
               "each wheel notch steps one row in its direction")
        suite.expect(feed(-8, phased: false) == 0 && feed(-8, phased: false) == 0 && feed(-8, phased: false) == 1
               && feed(-8, phased: false) == 0,
               "a smoothed wheel glide steps once for its notch")
        suite.expect(feed(-8, phased: false, after: 0.5) == 0 && feed(-8, phased: false) == 0 && feed(-8, phased: false) == 1,
               "a paused glide sequence starts over, so the next notch steps its own row")
        suite.expect(feed(-100, phased: false) == 1 && feed(-100, phased: false, after: -1) == 1,
               "a clock that runs backwards starts a fresh sequence instead of stalling")
        suite.expect(feed(.nan) == 0 && feed(-24, began: true) == 1,
               "an unreadable delta resets the sequence and the next gesture begins cleanly")
        suite.expect(feed(-10, began: true) == 0 && feed(-10, began: true) == 0 && feed(-10) == 0 && feed(-5) == 1,
               "a new beginning discards the previous gesture's distance")
        routing(suite)
    }

    /// A scroll that stays inside this test and never posts input to the desktop.
    struct Event: NotchScrollEvent {
        var locationInWindow: CGPoint
        var scrollingDeltaY: CGFloat = -24
        var timestamp: TimeInterval = 10
        var hasPreciseScrollingDeltas = true
        var phase: NSEvent.Phase = .began
        var momentumPhase: NSEvent.Phase = []
        var modifierFlags: NSEvent.ModifierFlags = []
    }

    final class Panel {
        let frame = CGRect(x: 173, y: 127, width: 600, height: 260)
        func convertPoint(toScreen point: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
        }
    }

    final class Host {
        var acceptsPoint = true
        func containsSurface(_ point: CGPoint) -> Bool { acceptsPoint }
    }

    private static func routing(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        for (width, cameraHeight) in [(600.0, 32.0), (400.0, 32.0), (600.0, 0.0), (600.0, 52.0)] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: cameraHeight, cameraWidth: 180,
                                         layout: .custom, customWidth: width, customHeight: 260)
            let panel = Panel()
            let host = Host()
            let surface = NotchSectionScrollSurface(frame: panel.frame, toScreen: panel.convertPoint(toScreen:),
                                                    containsSurface: host.containsSurface, geometry: geometry)
            var scroll = NotchSectionScroll()
            let headerBottom = geometry.headerTopInset + geometry.headerRowHeight
            func event(fromTop top: CGFloat) -> Event {
                Event(locationInWindow: CGPoint(x: 100, y: panel.frame.height - top))
            }
            suite.expect(scroll.route(event(fromTop: headerBottom), over: surface) == nil,
                         "the actual header keeps its gesture for width \(width) and camera height \(cameraHeight)")
            for offset in [1.0, NotchLayout.spacing + 1, NotchLayout.spacing + NotchLayout.sectionTileHeight / 2] {
                suite.expect(scroll.route(event(fromTop: headerBottom + offset), over: surface) == 1,
                             "every part of the body steps rows below the rendered header, including the top of the first tile")
            }
            var modified = event(fromTop: headerBottom + 20)
            modified.modifierFlags = .command
            suite.expect(scroll.route(modified, over: surface) == nil,
                         "modified scrolling is not captured by the gallery")
            suite.expect(scroll.route(event(fromTop: headerBottom + 20), over: nil) == nil,
                         "an island that is not showing the gallery leaves the scroll to its gestures")
            host.acceptsPoint = false
            suite.expect(scroll.route(event(fromTop: headerBottom + 20), over: surface) == nil,
                         "transparent corners and floating controls are not captured by the gallery")
        }

        // A drag that wanders off the gallery starts over when it comes back.
        let geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180,
                                     layout: .custom, customWidth: 600, customHeight: 260)
        let panel = Panel()
        let surface = NotchSectionScrollSurface(frame: panel.frame, toScreen: panel.convertPoint(toScreen:),
                                                containsSurface: { _ in true }, geometry: geometry)
        let body = CGPoint(x: 100, y: panel.frame.height - geometry.headerBottom - 20)
        var scroll = NotchSectionScroll()
        func drag(_ deltaY: CGFloat, at location: CGPoint, began: Bool = false) -> Int? {
            scroll.route(Event(locationInWindow: location, scrollingDeltaY: deltaY, phase: began ? .began : .changed),
                         over: surface)
        }
        suite.expect(drag(-10, at: body, began: true) == 0 && drag(-10, at: body) == 0,
                     "a short drag over the gallery has not stepped yet")
        let header = CGPoint(x: 100, y: panel.frame.height - 1)
        suite.expect(drag(-10, at: header) == nil && drag(-10, at: body) == 0,
                     "a scroll the gallery leaves to the header ends the drag it was part of")
        var command = Event(locationInWindow: body, scrollingDeltaY: -10, phase: .changed)
        command.modifierFlags = .command
        suite.expect(drag(-10, at: body) == 0 && scroll.route(command, over: surface) == nil
                     && drag(-10, at: body) == 0,
                     "a modified scroll ends the drag it was part of")
        suite.expect(drag(-10, at: body, began: true) == 0
                     && scroll.route(Event(locationInWindow: body, scrollingDeltaY: -20, phase: .ended),
                                     over: surface) == 0,
                     "lifting the fingers ends the drag without stepping")
        suite.expect(drag(-30, at: body, began: true) == 1
                     && scroll.route(Event(locationInWindow: body, scrollingDeltaY: -400, phase: [],
                                           momentumPhase: .changed), over: surface) == 0,
                     "momentum after the fingers lift is the gallery's but steps nothing")
        var notch = Event(locationInWindow: body, scrollingDeltaY: -1, phase: [])
        notch.hasPreciseScrollingDeltas = false
        suite.expect(scroll.route(notch, over: surface) == 1, "a wheel notch steps one row however small its delta")
        suite.expect(scroll.route(Event(locationInWindow: body, scrollingDeltaY: -20, timestamp: 20, phase: []),
                                  over: surface) == 0
                     && scroll.route(Event(locationInWindow: body, scrollingDeltaY: -20, timestamp: 20.5, phase: []),
                                     over: surface) == 0,
                     "a smooth wheel glide without phases ends when its events pause")
    }
}
