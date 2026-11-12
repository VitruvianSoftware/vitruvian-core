// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// A click selects a message (which shows its action bar), a second click on it deselects it, the second click of a
/// double click leaves it selected, and a click on the timeline's empty space deselects. The clicks are real mouse
/// events sent to a window holding the rows (ordered in, off the screen's edge), so SwiftUI decides who takes each
/// one, as it does in the app. A double click keeps the selection only because the timeline has its own tap
/// (`deselectsOnEmptyClick`): without it SwiftUI ends the row's single tap for the second click too, and the
/// double-click test fails, as it does with the empty-space one.
@MainActor
final class MessageSelectionClickTests: XCTestCase {
    private final class Box: ObservableObject {
        @Published var selected: String?
        @Published var frames: [String: CGRect] = [:]
    }

    /// Two messages in a scrolling timeline, as the chat's, taller than they are so there is empty space below them.
    private struct Harness: View {
        @ObservedObject var box: Box
        let items: [TimelineItem]
        let ui = MessageUI()

        var body: some View {
            let actions = VitruvianCourier.MessageActions(select: { box.selected = $0 }, deselect: { box.selected = nil },
                                                 now: { Fixture.now })
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        TimelineItemView(item: item, isSelected: box.selected == item.id, showsSent: false,
                                         actions: actions, ui: ui)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                box.frames[item.id] = $0
                            }
                    }
                }
                .padding(.horizontal, 14)
            }
            .deselectsOnEmptyClick { box.selected = nil }
            .environment(\.clickTargetProbe) { name, frame in box.frames[name] = frame }
            .frame(width: 600, height: 300)
        }
    }

    private var window: NSWindow!
    private var host: NSView!
    private let box = Box()
    private var lastClickTimestamp: TimeInterval = 0

    override func setUp() async throws {
        _ = NSApplication.shared
        let items = Fixture.items([
            Fixture.text("$a", "Are we still on for the hike on Saturday?", mine: false, ts: 9),
            Fixture.text("$b", "Yes, see you at eight.", mine: true, ts: 2),
            Fixture.event("$r", type: "m.reaction", mine: false, ts: 1, content: [
                "m.relates_to": .object([
                    "rel_type": .string("m.annotation"), "event_id": .string("$a"), "key": .string("👍"),
                ]),
            ], sender: "@bo:courier.local", name: "Bo Example"),
        ])
        let host = NSHostingView(rootView: Harness(box: box, items: items))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        // On screen, but off its edge: AppKit sends a window's clicks to SwiftUI's gestures only once it is ordered in.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        self.host = host
        settle()
    }

    override func tearDown() async throws {
        window.orderOut(nil)
        window.contentView = nil
        window = nil
    }

    private func settle(until condition: (() -> Bool)? = nil) {
        for _ in 0 ..< 25 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
            host.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    /// A click at a point in the host's coordinates (top-left origin), `count` being its place in a double click. A
    /// single click waits out the double-click interval first, as a person's separate clicks do: SwiftUI would take
    /// two quick clicks on one spot for a double click. When `settleUntil` is given (as on the first click of a double
    /// click), settling stops as soon as the condition holds so a loaded CI runner does not spend more than
    /// `NSEvent.doubleClickInterval` in `settle()` before the second click arrives.
    private func click(_ point: CGPoint, count: Int = 1, settleUntil: (() -> Bool)? = nil) throws {
        if count == 1 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: NSEvent.doubleClickInterval + 0.1))
        }
        let now = ProcessInfo.processInfo.systemUptime
        let timestamp = count > 1 ? min(now, lastClickTimestamp + 0.05) : now
        lastClickTimestamp = timestamp
        let location = NSPoint(x: point.x, y: host.bounds.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: timestamp,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1))
            NSApp.sendEvent(event)
        }
        settle(until: settleUntil)
    }

    /// The middle of a probed button in a row (`clickTargetProbe`): "chip/<message>/<key>", "add/<message>",
    /// "bar/<title>".
    private func point(ofButton name: String) throws -> CGPoint {
        let frame = try XCTUnwrap(box.frames[name], "button \(name) was laid out")
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The middle of a message's row, a little in from its bubble's side.
    private func point(in id: String) throws -> CGPoint {
        let frame = try XCTUnwrap(box.frames[id], "row \(id) was laid out")
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    func testAClickSelectsAndASecondClickDeselects() throws {
        let row = try point(in: "$a")
        try click(row)
        try XCTSkipIf(box.selected == nil, "the window got no clicks (no window server for it here)")
        XCTAssertEqual(box.selected, "$a", "a click selects the message")
        try click(row)
        XCTAssertNil(box.selected, "a click on the selected message deselects it")
    }

    func testTheSecondClickOfADoubleClickLeavesItSelected() throws {
        let row = try point(in: "$b")
        try click(row, count: 1, settleUntil: { [box] in box.selected == "$b" })
        try XCTSkipIf(box.selected == nil, "the window got no clicks (no window server for it here)")
        try click(row, count: 2)
        XCTAssertEqual(box.selected, "$b")
    }

    func testAClickOnAnotherMessageMovesTheSelection() throws {
        try click(try point(in: "$a"))
        try XCTSkipIf(box.selected == nil, "the window got no clicks (no window server for it here)")
        try click(try point(in: "$b"))
        XCTAssertEqual(box.selected, "$b")
    }

    func testAClickOnEmptySpaceDeselects() throws {
        try click(try point(in: "$a"))
        try XCTSkipIf(box.selected == nil, "the window got no clicks (no window server for it here)")
        let below = try XCTUnwrap(box.frames["$b"]).maxY + 40
        XCTAssertLessThan(below, host.bounds.height, "there is empty space below the messages")
        try click(CGPoint(x: 300, y: below))
        XCTAssertNil(box.selected, "a click below the messages deselects")
    }

    /// A click on a reaction chip of the selected message reacts; it must not deselect the message as well.
    func testAClickOnAReactionChipKeepsTheSelection() throws {
        try click(try point(in: "$a"))
        try XCTSkipIf(box.selected == nil, "the window got no clicks (no window server for it here)")
        try click(try point(ofButton: "chip/$a/👍"))
        XCTAssertEqual(box.selected, "$a", "the chip took the click, not the row")
    }

    /// The add-reaction chip after the chips shows once the message is selected; a click on it is the chip's.
    func testAClickOnTheAddReactionChipKeepsTheSelection() throws {
        try click(try point(in: "$a"))
        try XCTSkipIf(box.selected == nil, "the window got no clicks (no window server for it here)")
        try click(try point(ofButton: "add/$a"))
        XCTAssertEqual(box.selected, "$a")
    }

    /// The action bar's buttons are drawn outside the row's click, so they never toggle the selection.
    func testAClickOnTheActionBarKeepsTheSelection() throws {
        try click(try point(in: "$a"))
        try XCTSkipIf(box.selected == nil, "the window got no clicks (no window server for it here)")
        try click(try point(ofButton: "bar/Reply"))
        XCTAssertEqual(box.selected, "$a")
        try click(try point(ofButton: "bar/React with ❤️"))
        XCTAssertEqual(box.selected, "$a")
    }
}
