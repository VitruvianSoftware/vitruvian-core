// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// The chat's header is also the window's title: a click opens Chat Info, a drag moves the window and a double click
/// does the title bar's action, as in Finder.
final class ChatHeaderInteractionTests: XCTestCase {
    func testAClickWithoutMovementTogglesChatInfo() {
        var pointer = ChatHeaderPointer()
        pointer.mouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertNil(pointer.mouseDragged(to: CGPoint(x: 12, y: 11)), "a shake under the threshold is still a click")
        XCTAssertEqual(pointer.mouseUp(clickCount: 1), .toggleInfo)
    }

    func testADragMovesTheWindowOnceAndDoesNotToggle() {
        var pointer = ChatHeaderPointer()
        pointer.mouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertNil(pointer.mouseDragged(to: CGPoint(x: 11, y: 10)))
        XCTAssertEqual(pointer.mouseDragged(to: CGPoint(x: 10 + ChatHeaderPointer.dragThreshold, y: 10)), .beginWindowDrag)
        XCTAssertNil(pointer.mouseDragged(to: CGPoint(x: 80, y: 40)), "the window is handed the drag once")
        XCTAssertNil(pointer.mouseUp(clickCount: 1), "a drag is not a click")
    }

    func testADragAwayAndBackIsStillADrag() {
        var pointer = ChatHeaderPointer()
        pointer.mouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertEqual(pointer.mouseDragged(to: CGPoint(x: 60, y: 10)), .beginWindowDrag)
        XCTAssertNil(pointer.mouseDragged(to: CGPoint(x: 10, y: 10)))
        XCTAssertNil(pointer.mouseUp(clickCount: 1))
    }

    func testTheSecondClickOfADoubleClickIsTheTitleBars() {
        var pointer = ChatHeaderPointer()
        pointer.mouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertEqual(pointer.mouseUp(clickCount: 1), .toggleInfo, "the first click is a click")
        pointer.mouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertEqual(pointer.mouseUp(clickCount: 2), .doubleClick)
    }

    func testAnUpWithNoDownDoesNothingAndAClickAfterADragStillWorks() {
        var pointer = ChatHeaderPointer()
        XCTAssertNil(pointer.mouseUp(clickCount: 1))
        pointer.mouseDown(at: .zero)
        _ = pointer.mouseDragged(to: CGPoint(x: 50, y: 0))
        _ = pointer.mouseUp(clickCount: 1)
        pointer.mouseDown(at: .zero)
        XCTAssertEqual(pointer.mouseUp(clickCount: 1), .toggleInfo)
    }

    func testTheSystemsDoubleClickSetting() {
        func action(_ value: String?, legacy: Bool? = nil) -> TitleBarDoubleClickAction {
            TitleBarDoubleClickAction.from(actionValue: value, miniaturizeOnDoubleClick: legacy)
        }
        XCTAssertEqual(action("Maximize"), .zoom)
        XCTAssertEqual(action("Fill"), .zoom)
        XCTAssertEqual(action("Minimize"), .minimize)
        XCTAssertEqual(action("None"), TitleBarDoubleClickAction.none)
        XCTAssertEqual(action(nil), .zoom, "no setting: zoom, as the system does")
        XCTAssertEqual(action(nil, legacy: true), .minimize, "the older switch counts only without the new one")
        XCTAssertEqual(action("Maximize", legacy: true), .zoom)
        XCTAssertEqual(action("something new"), .zoom)
    }

    func testTheSettingIsReadFromTheDefaults() {
        let name = "courier.titlebar.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(TitleBarDoubleClickAction.current(defaults: defaults), .zoom)
        defaults.set("Minimize", forKey: "AppleActionOnDoubleClick")
        XCTAssertEqual(TitleBarDoubleClickAction.current(defaults: defaults), .minimize)
        defaults.set("None", forKey: "AppleActionOnDoubleClick")
        XCTAssertEqual(TitleBarDoubleClickAction.current(defaults: defaults), TitleBarDoubleClickAction.none)
    }

    func testVoiceOverReadsTheTitleThenTheNetworkAndTimer() {
        XCTAssertEqual(ChatHeaderAccessibility.label(title: "Book club"), "Book club")
        XCTAssertEqual(ChatHeaderAccessibility.value(subtitle: "Slack · 5 members", timer: "Messages disappear after 7 days"),
                       "Slack · 5 members, Messages disappear after 7 days")
        XCTAssertEqual(ChatHeaderAccessibility.value(subtitle: "Slack", timer: nil), "Slack")
        XCTAssertEqual(ChatHeaderAccessibility.value(subtitle: nil, timer: "7 days"), "7 days")
        XCTAssertEqual(ChatHeaderAccessibility.value(subtitle: nil, timer: nil), "")
        XCTAssertEqual(ChatHeaderAccessibility.hint(isShowing: false), "Shows chat info")
        XCTAssertEqual(ChatHeaderAccessibility.hint(isShowing: true), "Hides chat info")
    }
}
