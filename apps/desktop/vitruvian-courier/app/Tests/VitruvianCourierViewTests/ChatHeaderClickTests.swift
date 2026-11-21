// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// A click on the chat's picture, name or network in its header shows Chat Info, and another hides it: the same as the
/// ⓘ button. The clicks are real mouse events sent to a window holding the header (ordered in, off the screen's edge),
/// as `MessageSelectionClickTests` does.
@MainActor
final class ChatHeaderClickTests: XCTestCase {
    private var window: NSWindow!
    private var host: NSView!
    private var conversation: ConversationModel!
    private var suiteName: String?
    /// A button under the header that does nothing but count its clicks: a click that reaches it proves the window
    /// gets clicks at all, so a header that does not react is a defect and not a missing window server.
    private final class Canary: ObservableObject { var clicks = 0 }
    private let canary = Canary()
    private static let canaryHeight: CGFloat = 24

    override func setUp() async throws {
        _ = NSApplication.shared
        let name = "courier.header-click.\(UUID().uuidString)"
        suiteName = name
        let store = try XCTUnwrap(ScratchDefaults.suite(named: name))
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-header-click"),
            environment: [:], launcher: FoundationProcessLauncher()))
        let preferences = ComposerPreferences(defaults: store)
        conversation = ConversationModel(appModel: app, preferences: preferences)
        let row = Fixture.row("!hdr", "Book club", network: "slack", direct: false, ts: 9, preview: "hi")
        conversation.setSnapshotStateForTesting(roomID: "!hdr", items: [], row: row, features: Fixture.features)

        let header = ConversationHeader(row: row, displayTitle: nil, networkName: "Slack", conversation: conversation,
                                        part: .strip)
        let canary = canary
        let height = PaneHeaderMetrics.stripHeight + Self.canaryHeight
        let hosting = NSHostingView(rootView: VStack(spacing: 0) {
            header.frame(width: 700, height: PaneHeaderMetrics.stripHeight)
            Button { canary.clicks += 1 } label: { Color.clear.frame(width: 700, height: Self.canaryHeight).contentShape(Rectangle()) }
                .buttonStyle(.plain)
        })
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: height)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        host = hosting
        settle()
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        if let suiteName { ScratchDefaults.suite(named: suiteName)?.removePersistentDomain(forName: suiteName) }
    }

    private func settle() {
        for _ in 0 ..< 25 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
            host.layoutSubtreeIfNeeded()
        }
    }

    /// A click at a point in the host's coordinates (top-left origin).
    private func click(_ point: CGPoint) throws {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: NSEvent.doubleClickInterval + 0.1))
        let now = ProcessInfo.processInfo.systemUptime
        let location = NSPoint(x: point.x, y: host.bounds.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: now,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
        settle()
    }

    private let mid = PaneHeaderMetrics.stripHeight / 2
    /// The picture is 28 pt, after the header's inset.
    private var picture: CGPoint { CGPoint(x: PaneHeaderMetrics.inset + 14, y: mid) }
    /// The name starts after the picture and its 10 pt gap.
    private var nameSpot: CGPoint { CGPoint(x: PaneHeaderMetrics.inset + 28 + 10 + 20, y: mid - 6) }
    private var networkSpot: CGPoint { CGPoint(x: PaneHeaderMetrics.inset + 28 + 10 + 20, y: mid + 8) }

    /// Skips unless the window takes clicks at all (it does where there is a window server).
    private func requireClicksWork() throws {
        try click(CGPoint(x: 350, y: PaneHeaderMetrics.stripHeight + Self.canaryHeight / 2))
        try XCTSkipIf(canary.clicks == 0, "the window got no clicks (no window server for it here)")
    }

    func testAClickOnThePictureTogglesChatInfo() throws {
        try requireClicksWork()
        XCTAssertFalse(conversation.isShowingChatInfo)
        try click(picture)
        XCTAssertTrue(conversation.isShowingChatInfo, "a click on the picture shows it")
        try click(picture)
        XCTAssertFalse(conversation.isShowingChatInfo, "a second click hides it")
    }

    func testAClickOnTheNameOrNetworkTogglesChatInfo() throws {
        try requireClicksWork()
        try click(nameSpot)
        XCTAssertTrue(conversation.isShowingChatInfo, "a click on the name shows it")
        try click(networkSpot)
        XCTAssertFalse(conversation.isShowingChatInfo, "a click on the network hides it")
    }

    func testAClickAwayFromTheNameDoesNothing() throws {
        try requireClicksWork()
        // Anywhere in the middle of the header, well past the name.
        try click(CGPoint(x: 400, y: mid))
        XCTAssertFalse(conversation.isShowingChatInfo, "only the picture and the name are the button")
    }
}
