// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// The live case behind batch 6 D1 (Courier 0.3.31, a Google Chat group): the oldest loaded message had no date
/// divider above it. A chat that is longer than the window, scrolled to the top of what is loaded, must show a day
/// divider as its first row, whether or not older pages may still come.
@MainActor
final class DateDividerTopOfHistoryViewTests: XCTestCase {
    private var suites: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
    }

    private func pump(_ host: NSView, for interval: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    private struct Root: View {
        @ObservedObject var conversation: ConversationModel
        @ObservedObject var messageActions: MessageActionsModel
        let prefs: ComposerPreferences
        let ui: MessageUI
        let app: AppModel

        var body: some View {
            let actions = VitruvianCourier.MessageActions(
                select: { conversation.selectedMessageID = $0 },
                deselect: { conversation.deselectMessage() },
                reply: { _ in },
                now: { Fixture.now }
            )
            TimelineTableView(
                conversation: conversation,
                messageActions: messageActions,
                preferences: prefs,
                ui: ui,
                appModel: app,
                actions: actions,
                effectiveHeaderInset: 48,
                bottomSafeAreaInset: 0,
                bottomBarSignature: [],
                resolvedAppearance: nil,
                redact: false,
                themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                drawsLiquidGlass: false,
                timelineCovered: false
            )
        }
    }

    private func check(hasOlder: Bool) throws {
        _ = NSApplication.shared
        let name = "courier.d1top.\(UUID().uuidString)"
        suites.append(name)
        let store = ScratchDefaults.suite(named: name)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("courier-d1top-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine", dataDir: dir, environment: [:],
            launcher: FoundationProcessLauncher()))
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard())
        let ui = MessageUI()

        // 40 messages, three hours apart: several days, far taller than the window.
        let events = (0 ..< 40).map { i in
            Fixture.text("$m\(i)", "Message number \(i)", mine: i % 3 == 0, ts: (40 - i) * 180)
        }
        let items = Fixture.items(events, isDirect: false)
        XCTAssertTrue({ if case .dateSeparator = items[0] { true } else { false } }(), "Timeline.build starts with a day")
        conversation.setSnapshotStateForTesting(
            roomID: "!d1-top", items: items,
            row: Fixture.row("!d1-top", "Group", network: "googlechat", direct: false, ts: 180, preview: "hi"),
            features: Fixture.features, hasOlder: hasOlder)

        let size = NSSize(width: 640, height: 320)
        let host = NSHostingView(rootView: Root(
            conversation: conversation, messageActions: messageActions, prefs: prefs, ui: ui, app: app))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }

        pump(host, for: 0.6) { host.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(host, for: 1.0) { coordinator.entries.count >= items.count && tableView.numberOfRows == coordinator.entries.count }
        pump(host, for: 0.5)

        let firstContent = hasOlder ? 1 : (coordinator.entries.first?.kind == .topControl ? 1 : 0)
        XCTAssertTrue(coordinator.entries[firstContent].id.hasPrefix("day-"),
                      "first row after the top control is a day: \(coordinator.entries.prefix(4).map(\.id))")

        // Scroll to the very top of what is loaded and look at what is on screen.
        let scrollView = try XCTUnwrap(tableView.enclosingScrollView)
        let clip = scrollView.contentView
        coordinator.noteUserScrollForTesting() // a person scrolling ends the pin to the bottom that follows opening
        for _ in 0 ..< 4 {
            pump(host, for: 0.3)
            clip.scroll(to: NSPoint(x: 0, y: -scrollView.contentInsets.top))
            scrollView.reflectScrolledClipView(clip)
            if tableView.visibleRect.minY < 5 { break }
        }
        pump(host, for: 0.3)
        XCTAssertLessThan(tableView.visibleRect.minY, 5, "the test reached the top of the loaded history")
        let dayRow = firstContent
        let dayRect = tableView.rect(ofRow: dayRow)
        XCTAssertGreaterThan(dayRect.height, 10, "day divider has a height")
        let visible = tableView.visibleRect
        XCTAssertTrue(visible.intersects(dayRect), "the day divider (\(dayRect)) is on screen at the top (\(visible))")
        XCTAssertNotNil(tableView.view(atColumn: 0, row: dayRow, makeIfNecessary: false), "the divider row is built")
    }

    func testFirstLoadedRowIsADayDividerWhenNoOlderPagesRemain() throws { try check(hasOlder: false) }

    func testFirstLoadedRowIsADayDividerWhileOlderPagesMayStillCome() throws { try check(hasOlder: true) }
}
