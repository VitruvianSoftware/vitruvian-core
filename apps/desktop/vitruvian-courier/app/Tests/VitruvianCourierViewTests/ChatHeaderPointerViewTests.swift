// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// The header's mouse view: a click toggles Chat Info, a drag hands the mouse to the window, a double click does the
/// title bar's action (and leaves Chat Info as it was), and the pointing hand is a cursor rect, not a pushed cursor.
@MainActor
final class ChatHeaderPointerViewTests: XCTestCase {
    private final class Spy: ChatHeaderPointerNSView {
        var cursorRects: [(NSRect, NSCursor)] = []
        override func addCursorRect(_ rect: NSRect, cursor: NSCursor) { cursorRects.append((rect, cursor)) }
    }

    private final class Counts {
        var toggles = 0
        var drags = 0
        var performed: [TitleBarDoubleClickAction] = []
    }

    private func make(setting: TitleBarDoubleClickAction = .zoom) -> (Spy, Counts) {
        let counts = Counts()
        let view = Spy(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        view.onToggle = { counts.toggles += 1 }
        view.beginWindowDrag = { _ in counts.drags += 1 }
        view.doubleClickAction = { setting }
        view.perform = { action, _ in counts.performed.append(action) }
        return (view, counts)
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint, clickCount: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1))
    }

    func testAClickTogglesChatInfoOnce() throws {
        let (view, counts) = make()
        view.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 20, y: 20)))
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 20, y: 20)))
        XCTAssertEqual(counts.toggles, 1)
        XCTAssertEqual(counts.drags, 0)
        XCTAssertTrue(counts.performed.isEmpty)
    }

    func testADragMovesTheWindowAndDoesNotToggle() throws {
        let (view, counts) = make()
        view.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 20, y: 20)))
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 21, y: 20)))
        XCTAssertEqual(counts.drags, 0, "a shake under the threshold is not a drag")
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 90, y: 30)))
        view.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 120, y: 30)))
        view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 120, y: 30)))
        XCTAssertEqual(counts.drags, 1, "the window is handed the drag once")
        XCTAssertEqual(counts.toggles, 0, "dragging the title is not a click on it")
    }

    func testADoubleClickDoesTheSystemActionAndLeavesChatInfoAsItWas() throws {
        for setting in [TitleBarDoubleClickAction.zoom, .minimize, .none] {
            let (view, counts) = make(setting: setting)
            view.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 20, y: 20)))
            view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 20, y: 20)))
            view.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 20, y: 20), clickCount: 2))
            view.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 20, y: 20), clickCount: 2))
            XCTAssertEqual(counts.toggles, 2, "the first click opened it and the double click shuts it again")
            XCTAssertEqual(counts.performed, [setting], "the person's setting: \\(setting)")
        }
    }

    func testThePointingHandIsACursorRectOverTheWholeView() {
        let (view, _) = make()
        view.resetCursorRects()
        XCTAssertEqual(view.cursorRects.count, 1)
        XCTAssertEqual(view.cursorRects.first?.0, view.bounds)
        XCTAssertTrue(view.cursorRects.first?.1 === NSCursor.pointingHand)
    }

    func testTheViewIsNotMovableByItsWindowSoItGetsItsOwnClicks() {
        let (view, _) = make()
        XCTAssertFalse(view.mouseDownCanMoveWindow)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil), "a click on an inactive window's header still works")
    }
}
