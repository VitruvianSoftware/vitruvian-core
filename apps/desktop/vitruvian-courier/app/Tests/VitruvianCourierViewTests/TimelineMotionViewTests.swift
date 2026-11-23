// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

@MainActor
final class TimelineMotionViewTests: XCTestCase {
    private var suites: [String] = []
    /// How long the last `mountTable` took until the table was on screen.
    private var mountSeconds: Double = 0
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
    }

    private func makeDefaults() -> UserDefaults {
        let name = "courier.motionviewtests.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-motion-view-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private struct ObservingTimeline<Content: View>: View {
        @ObservedObject var conversation: ConversationModel
        @ObservedObject var messageActions: MessageActionsModel
        @ViewBuilder let content: () -> Content

        var body: some View { content() }
    }

    @MainActor
    private struct TableHarness {
        let conversation: ConversationModel
        let container: TimelineContainerView
        let tableView: TimelineNSTableView
        let scrollView: NSScrollView
        let coordinator: TimelineTableView.Coordinator
        let window: NSWindow
        let host: NSView
        let bottomInsetBox: Box

        final class Box: ObservableObject {
            @Published var bottomSafeAreaInset: CGFloat = 0
        }

        func pump(for interval: TimeInterval, until condition: (() -> Bool)? = nil) {
            let deadline = Date().addingTimeInterval(interval)
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                host.layoutSubtreeIfNeeded()
                if condition?() == true { break }
            }
        }

        func scrollBy(_ deltaY: CGFloat) {
            coordinator.noteUserScrollForTesting()
            let clip = scrollView.contentView
            let proposed = NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + deltaY)
            clip.scroll(to: proposed)
            scrollView.reflectScrolledClipView(clip)
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
        }

        func tearDown() {
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    private func mountTable(
        items: [TimelineItem],
        lastOutgoingID: String? = nil,
        hasOlder: Bool = false,
        size: NSSize = NSSize(width: 600, height: 500),
        effectiveHeaderInset: CGFloat = 48
    ) throws -> TableHarness {
        _ = NSApplication.shared
        let store = makeDefaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: try makeTempDir(), environment: [:], launcher: FoundationProcessLauncher()
        ))
        let preferences = ComposerPreferences(defaults: store)
        preferences.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: preferences)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: preferences, pasteboard: NoPasteboard()
        )
        let ui = MessageUI()
        conversation.setSnapshotStateForTesting(
            roomID: "!motion-view-test",
            items: items,
            row: Fixture.row("!motion-view-test", "Motion Chat", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features,
            lastOutgoingID: lastOutgoingID,
            hasOlder: hasOlder
        )

        let box = TableHarness.Box()
        let rootView = ObservingTimeline(conversation: conversation, messageActions: messageActions) {
            BottomInsetHost(
                box: box,
                conversation: conversation,
                messageActions: messageActions,
                preferences: preferences,
                ui: ui,
                appModel: app,
                effectiveHeaderInset: effectiveHeaderInset
            )
        }
        .environment(\.liquidGlass, false)

        let host = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()

        let mountStarted = CFAbsoluteTimeGetCurrent()
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            if host.first(TimelineNSTableView.self) != nil { break }
        }

        mountSeconds = CFAbsoluteTimeGetCurrent() - mountStarted
        let container = try XCTUnwrap(host.first(TimelineContainerView.self))
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        let harness = TableHarness(
            conversation: conversation,
            container: container,
            tableView: tableView,
            scrollView: scrollView,
            coordinator: coordinator,
            window: window,
            host: host,
            bottomInsetBox: box
        )
        harness.pump(for: 0.2)
        return harness
    }

    private struct BottomInsetHost: View {
        @ObservedObject var box: TableHarness.Box
        // Observed here, not only by the wrapper: SwiftUI skips the body of a view whose inputs did not change, so
        // without this the table never saw the items these tests change.
        @ObservedObject var conversation: ConversationModel
        @ObservedObject var messageActions: MessageActionsModel
        let preferences: ComposerPreferences
        let ui: MessageUI
        let appModel: AppModel
        let effectiveHeaderInset: CGFloat

        var body: some View {
            let actions = MessageRowActions.make(
                conversation: conversation, messageActions: messageActions, preferences: preferences,
                composer: conversation.composer, ui: ui, source: .chat,
                deselect: { conversation.deselectMessage() }, select: { conversation.selectedMessageID = $0 }
            )
            TimelineTableView(
                conversation: conversation,
                messageActions: messageActions,
                preferences: preferences,
                ui: ui,
                appModel: appModel,
                actions: actions,
                effectiveHeaderInset: effectiveHeaderInset,
                bottomSafeAreaInset: box.bottomSafeAreaInset,
                bottomBarSignature: [],
                resolvedAppearance: nil,
                redact: false,
                themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                drawsLiquidGlass: false,
                timelineCovered: false
            )
        }
    }

    // MARK: - Item 1: Delayed Spinner Threshold (250 ms)

    func testPendingRoomSpinnerWaitsQuarterSecondBeforeShowing() throws {
        let events = [Fixture.text("$1", "Hello", mine: false, ts: 5)]
        let harness = try mountTable(items: Fixture.items(events))
        defer { harness.tearDown() }

        XCTAssertFalse(harness.container.isPendingSpinnerVisibleForTesting)
        harness.container.setPendingRoomLoading(true)
        harness.pump(for: 0.10)
        XCTAssertFalse(harness.container.isPendingSpinnerVisibleForTesting, "spinner stays hidden before 250 ms")

        harness.pump(for: 0.25) { harness.container.isPendingSpinnerVisibleForTesting }
        XCTAssertTrue(harness.container.isPendingSpinnerVisibleForTesting, "spinner appears once loading exceeds 250 ms")

        harness.container.setPendingRoomLoading(false)
        harness.pump(for: 0.05)
        XCTAssertFalse(harness.container.isPendingSpinnerVisibleForTesting)
    }

    // MARK: - Item 1: Cold Open Of A Full Page

    /// Fifty rows of mixed length, the size of the first page of a long chat.
    private func fullPage() -> [TimelineItem] {
        let long = String(repeating: "A longer message that wraps over several lines in the pane. ", count: 4)
        let events = (1 ... 50).map { i in
            Fixture.text("$p\(i)", i % 3 == 0 ? long : "Message \(i)", mine: i % 2 == 0, ts: 200 - i)
        }
        return Fixture.items(events)
    }

    /// Measures (not asserts) how long the first layout of a full page takes in this build, and prints it; the result
    /// that decided where item 1's time goes is quoted in the change description.
    func testColdOpenOfAFullPageIsMeasured() throws {
        let started = CFAbsoluteTimeGetCurrent()
        let harness = try mountTable(items: fullPage(), size: NSSize(width: 700, height: 600))
        defer { harness.tearDown() }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        print("COLD_OPEN_FULL_PAGE_SECONDS first_layout=\(String(format: "%.3f", mountSeconds)) total=\(String(format: "%.3f", elapsed)) (total includes the 0.2 s settle pump)")
        XCTAssertEqual(harness.coordinator.entries.count, harness.tableView.numberOfRows)
    }

    /// A cold open measures only the rows near the bottom at first; the older ones are measured right after. The
    /// newest row must stay flush above the bottom edge and the rows on screen must not move while that catches up.
    func testColdOpenOfAFullPageStaysAtTheBottomWhileOlderRowsAreMeasured() throws {
        let harness = try mountTable(items: fullPage(), size: NSSize(width: 700, height: 600))
        defer { harness.tearDown() }
        func frame(_ id: String) throws -> CGRect {
            let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == id })
            return harness.host.convert(harness.tableView.rect(ofRow: row), from: harness.tableView)
        }
        let newestAtOnce = try frame("$p50")
        XCTAssertEqual(newestAtOnce.maxY, 600 - ConversationView.timelineVerticalPadding, accuracy: 2.0,
                       "the newest message sits at the bottom right after the open")
        let neighbourAtOnce = try frame("$p49")
        harness.pump(for: 1.0)
        XCTAssertEqual(try frame("$p50").maxY, newestAtOnce.maxY, accuracy: 1.0, "the newest row does not move")
        XCTAssertEqual(try frame("$p49").minY, neighbourAtOnce.minY, accuracy: 1.0,
                       "the rows on screen do not move while older rows are measured")
        XCTAssertTrue(harness.conversation.isAtBottom)
    }

    // MARK: - Item 7: Sent Message Rise-In Plays Once

    func testSentMessageRisePlaysOnceAtBottomAndNeverWhenScrolledUp() throws {
        let initial = (1 ... 25).map {
            Fixture.text("$m\($0)", "Message \($0)", mine: $0 % 2 == 0, ts: 40 - $0)
        }
        let harness = try mountTable(items: Fixture.items(initial), size: NSSize(width: 600, height: 360))
        defer { harness.tearDown() }

        // 1. Local send at bottom attaches rise animation on initial insertion of the new row.
        harness.conversation.recordLocalSendForTesting("$sent1")
        let appended = initial + [Fixture.text("$sent1", "Just sent!", mine: true, ts: 1, status: .pending)]
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(appended))
        harness.pump(for: 0.25) {
            harness.coordinator.entries.contains { $0.id == "$sent1" }
        }

        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$sent1" })
        let cell = try XCTUnwrap(harness.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineCell)
        XCTAssertTrue(cell.hasActiveSentRiseAnimationForTesting, "freshly sent message at bottom must animate in")

        // Let animation finish and verify scrolling away and back never replays it.
        harness.pump(for: 0.35)
        XCTAssertFalse(cell.hasActiveSentRiseAnimationForTesting)
        harness.scrollBy(-200)
        harness.pump(for: 0.05)
        harness.scrollBy(200)
        harness.pump(for: 0.05)
        let rowAfterScrollBack = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$sent1" })
        if let revisitedCell = harness.tableView.view(atColumn: 0, row: rowAfterScrollBack, makeIfNecessary: false) as? TimelineCell {
            XCTAssertFalse(revisitedCell.hasActiveSentRiseAnimationForTesting, "must never replay on scroll back")
        }

        // 2. Scrolled away from bottom: local send does not animate.
        harness.scrollBy(-220)
        harness.pump(for: 0.05)
        XCTAssertFalse(harness.conversation.isAtBottom)
        harness.conversation.recordLocalSendForTesting("$sentUp")
        XCTAssertFalse(
            harness.conversation.consumeSentMessageRise(
                eventID: "$sentUp", isInitialRender: false, isHistoryLoad: false
            )
        )
    }

    /// Under Reduce Motion the rise is a fade only: nothing moves and nothing scales.
    func testSentMessageRiseUnderReduceMotionIsOnlyAFade() throws {
        let initial = (1 ... 6).map { Fixture.text("$r\($0)", "Message \($0)", mine: $0 % 2 == 0, ts: 40 - $0) }
        let harness = try mountTable(items: Fixture.items(initial), size: NSSize(width: 600, height: 400))
        defer { harness.tearDown() }
        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$r6" })
        let cell = try XCTUnwrap(harness.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineCell)

        cell.playSentMessageRiseAnimation(reduceMotion: true)
        XCTAssertEqual(cell.sentRiseAnimatedKeyPathsForTesting, ["opacity"], "Reduce Motion: a fade, no movement or scale")
        cell.prepareForReuse()
        XCTAssertFalse(cell.hasActiveSentRiseAnimationForTesting, "a reused cell never carries the rise")

        cell.playSentMessageRiseAnimation(reduceMotion: false)
        XCTAssertEqual(Set(cell.sentRiseAnimatedKeyPathsForTesting), ["opacity", "transform"])
    }

    // MARK: - Item 8: No Jump on Sending -> Sent

    func testSendingToSentKeepsNewestBubbleAndGapUnchanged() throws {
        let older = Fixture.text("$older", "Previous outgoing message", mine: true, ts: 10, status: .sent)
        let sending = Fixture.text("$newest", "In-flight outgoing message", mine: true, ts: 2, status: .pending)
        let harness = try mountTable(
            items: Fixture.items([older, sending]),
            lastOutgoingID: nil,
            size: NSSize(width: 600, height: 400)
        )
        defer { harness.tearDown() }

        func rowFrameInHost(_ id: String) throws -> CGRect {
            let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == id })
            return harness.host.convert(harness.tableView.rect(ofRow: row), from: harness.tableView)
        }

        let olderBefore = try rowFrameInHost("$older")
        let newestBefore = try rowFrameInHost("$newest")
        let gapBefore = newestBefore.minY - olderBefore.maxY

        // Transition newest from Sending... to Sent.
        let sent = Fixture.text("$newest", "In-flight outgoing message", mine: true, ts: 2, status: .sent)
        harness.conversation.setSnapshotStateForTesting(
            roomID: "!motion-view-test",
            items: Fixture.items([older, sent]),
            row: Fixture.row("!motion-view-test", "Motion Chat", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features,
            lastOutgoingID: "$newest"
        )
        harness.pump(for: 0.15)

        let olderAfter = try rowFrameInHost("$older")
        let newestAfter = try rowFrameInHost("$newest")
        let gapAfter = newestAfter.minY - olderAfter.maxY

        XCTAssertEqual(olderAfter.minY, olderBefore.minY, accuracy: 0.5, "earlier bubble must not shift")
        XCTAssertEqual(newestAfter.minY, newestBefore.minY, accuracy: 0.5, "newest bubble must not jump vertically")
        XCTAssertEqual(newestAfter.height, newestBefore.height, accuracy: 0.5, "Sending and Sent share identical row height")
        XCTAssertEqual(gapAfter, gapBefore, accuracy: 0.5, "gap between bubbles must remain identical across Sending -> Sent")
    }

    // MARK: - Item 9: Short Chats Sit at the Bottom Across Resize, Composer Growth, and Older Loads

    func testShortChatSitsAtBottomAcrossResizeComposerGrowthAndOlderLoad() throws {
        let events = [
            Fixture.text("$s1", "First short message", mine: false, ts: 10),
            Fixture.text("$s2", "Second short message", mine: true, ts: 5, status: .sent),
        ]
        let harness = try mountTable(
            items: Fixture.items(events),
            lastOutgoingID: "$s2",
            size: NSSize(width: 600, height: 500),
            effectiveHeaderInset: 48
        )
        defer { harness.tearDown() }

        func rowFrameInHost(_ id: String) throws -> CGRect {
            let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == id })
            return harness.host.convert(harness.tableView.rect(ofRow: row), from: harness.tableView)
        }

        // 1. Sits flush above the bottom padding (500 - 8 = 492), NOT near the top header (48 + 8 = 56).
        let initialLast = try rowFrameInHost("$s2")
        XCTAssertGreaterThan(initialLast.minY, 300, "short chat sits near bottom, not under header")
        XCTAssertEqual(initialLast.maxY, 500 - ConversationView.timelineVerticalPadding, accuracy: 2.0)

        // 2. Window resize taller and shorter keeps it flush at bottom.
        let taller = NSSize(width: 600, height: 640)
        harness.window.setContentSize(taller)
        harness.host.frame = NSRect(origin: .zero, size: taller)
        harness.host.layoutSubtreeIfNeeded()
        harness.pump(for: 0.15)
        XCTAssertEqual(
            try rowFrameInHost("$s2").maxY,
            640 - ConversationView.timelineVerticalPadding,
            accuracy: 2.0,
            "stays anchored at bottom when resized taller"
        )

        let shorter = NSSize(width: 600, height: 380)
        harness.window.setContentSize(shorter)
        harness.host.frame = NSRect(origin: .zero, size: shorter)
        harness.host.layoutSubtreeIfNeeded()
        harness.pump(for: 0.15)
        XCTAssertEqual(
            try rowFrameInHost("$s2").maxY,
            380 - ConversationView.timelineVerticalPadding,
            accuracy: 2.0,
            "stays anchored at bottom when resized shorter"
        )

        // 3. Composer growth / typing line (simulated via bottomSafeAreaInset growth) shifts chat up cleanly above composer.
        harness.bottomInsetBox.bottomSafeAreaInset = 76
        harness.pump(for: 0.15)
        XCTAssertEqual(
            try rowFrameInHost("$s2").maxY,
            380 - 76 - ConversationView.timelineVerticalPadding,
            accuracy: 2.0,
            "stays anchored just above expanded composer / typing line"
        )

        // 4. Prepending older messages keeps short chat anchored without jumping, then transitions to tall seamlessly.
        harness.bottomInsetBox.bottomSafeAreaInset = 0
        harness.pump(for: 0.15)
        let beforePrependS1MinY = try rowFrameInHost("$s1").minY
        let twoOlder = (1 ... 2).map { Fixture.text("$o\($0)", "Older \($0)", mine: false, ts: 40 - $0) }
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(twoOlder + events))
        harness.pump(for: 0.15)
        XCTAssertEqual(
            try rowFrameInHost("$s1").minY, beforePrependS1MinY, accuracy: 1.5,
            "prepending older messages in a still-short chat keeps existing rows stationary"
        )
        XCTAssertEqual(
            try rowFrameInHost("$s2").maxY,
            380 - ConversationView.timelineVerticalPadding,
            accuracy: 2.0
        )

        let manyOlder = (1 ... 25).map { Fixture.text("$old\($0)", "History #\($0)", mine: false, ts: 100 - $0) }
        let beforeTallPrependS1MinY = try rowFrameInHost("$s1").minY
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(manyOlder + twoOlder + events))
        harness.pump(for: 0.2)
        XCTAssertEqual(
            try rowFrameInHost("$s1").minY, beforeTallPrependS1MinY, accuracy: 2.0,
            "crossing from short to tall keeps existing rows stationary without bounce"
        )
    }

    // MARK: - Item 20: Highlight Duration

    func testJumpHighlightDurationIsOneAndAHalfSeconds() {
        XCTAssertEqual(ConversationModel.highlightDuration, .milliseconds(1500))
    }
}
