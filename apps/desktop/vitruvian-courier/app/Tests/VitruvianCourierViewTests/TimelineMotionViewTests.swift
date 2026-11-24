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

    // MARK: - Item 1: Cold Open Of A Full Page

    /// Fifty rows of mixed length, the size of the first page of a long chat.
    private func fullPageEvents() -> [Event] {
        let long = String(repeating: "A longer message that wraps over several lines in the pane. ", count: 4)
        return (1 ... 50).map { i in
            Fixture.text("$p\(i)", i % 3 == 0 ? long : "Message \(i)", mine: i % 2 == 0, ts: 200 - i)
        }
    }

    private func fullPage() -> [TimelineItem] { Fixture.items(fullPageEvents()) }

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

    /// The rise starts 14 pt below where the bubble rests and scales about its bottom-right corner, whichever way the
    /// layer's parent counts y. Checked in the window's own (y-up) layer space, so it fails if the shift is upward.
    func testRiseStartsFourteenPointsBelowAndScalesAboutTheBottomRightCorner() throws {
        let initial = (1 ... 6).map { Fixture.text("$r\($0)", "Message \($0)", mine: $0 % 2 == 0, ts: 40 - $0) }
        let harness = try mountTable(items: Fixture.items(initial), size: NSSize(width: 600, height: 400))
        defer { harness.tearDown() }
        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$r6" })
        let cell = try XCTUnwrap(harness.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineCell)
        let layer = try XCTUnwrap(cell.hostingView.layer)

        cell.playSentMessageRiseAnimation(reduceMotion: false)
        let group = try XCTUnwrap(layer.animation(forKey: "courier.sentMessageRise") as? CAAnimationGroup)
        let rise = try XCTUnwrap((group.animations ?? []).compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "transform" })
        let from = try XCTUnwrap((rise.fromValue as? NSValue)?.caTransform3DValue)

        var root = layer
        while let up = root.superlayer { root = up }
        XCTAssertFalse(root.isGeometryFlipped, "the window's root layer is the right way up: lower on screen is smaller y")

        let size = layer.bounds.size
        // Of the two right-hand corners, the one lower on screen has the smaller y in the root layer.
        func rootPoint(_ p: CGPoint) -> CGPoint { layer.convert(p, to: root) }
        layer.removeAllAnimations()
        let resting = [CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height)].map(rootPoint)
        let lowerIndex = resting[0].y < resting[1].y ? 0 : 1
        let bottomRight = [CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height)][lowerIndex]
        let topLeft = [CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0)][lowerIndex]
        let restBottomRight = rootPoint(bottomRight)
        let restTopLeft = rootPoint(topLeft)

        layer.transform = from
        let startBottomRight = rootPoint(bottomRight)
        let startTopLeft = rootPoint(topLeft)
        layer.transform = CATransform3DIdentity

        XCTAssertEqual(startBottomRight.y - restBottomRight.y, -14, accuracy: 0.5,
                       "the corner starts 14 pt lower on screen (smaller y in the y-up root)")
        XCTAssertEqual(startBottomRight.x - restBottomRight.x, 0, accuracy: 0.5, "the bottom-right corner is the pivot")
        let restSpan = hypot(restTopLeft.x - restBottomRight.x, restTopLeft.y - restBottomRight.y)
        let startSpan = hypot(startTopLeft.x - startBottomRight.x, startTopLeft.y - startBottomRight.y)
        XCTAssertEqual(startSpan / restSpan, 0.97, accuracy: 0.002, "scaled to 0.97 about that corner")
    }

    /// The production path under Reduce Motion: a send at the bottom fades in and does not move or scale.
    func testASendAtTheBottomUnderReduceMotionOnlyFades() throws {
        let initial = (1 ... 6).map { Fixture.text("$r\($0)", "Message \($0)", mine: $0 % 2 == 0, ts: 40 - $0) }
        let harness = try mountTable(items: Fixture.items(initial), size: NSSize(width: 600, height: 400))
        defer { harness.tearDown() }
        harness.coordinator.reduceMotionOverrideForTesting = true
        harness.bottomInsetBox.bottomSafeAreaInset = 0.5 // makes SwiftUI hand the coordinator the environment again
        harness.pump(for: 0.1)

        harness.conversation.recordLocalSendForTesting("$sent")
        harness.conversation.setSnapshotItemsForTesting(
            Fixture.items(initial + [Fixture.text("$sent", "Just sent", mine: true, ts: 1, status: .pending)])
        )
        harness.pump(for: 0.3) { harness.coordinator.entries.contains { $0.id == "$sent" } }
        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$sent" })
        let cell = try XCTUnwrap(harness.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineCell)
        XCTAssertEqual(cell.sentRiseAnimatedKeyPathsForTesting, ["opacity"])
    }

    /// Reduce Motion: the jump to the latest goes straight there, with no 0.2 s glide.
    func testJumpToTheLatestIsImmediateUnderReduceMotion() throws {
        let events = (1 ... 40).map { Fixture.text("$j\($0)", "Message \($0)", mine: $0 % 2 == 0, ts: 100 - $0) }
        let harness = try mountTable(items: Fixture.items(events), size: NSSize(width: 600, height: 400))
        defer { harness.tearDown() }
        harness.coordinator.reduceMotionOverrideForTesting = true
        harness.bottomInsetBox.bottomSafeAreaInset = 0.5
        harness.pump(for: 0.1)
        harness.scrollBy(-500)
        harness.pump(for: 0.05)
        XCTAssertFalse(harness.conversation.isAtBottom)

        harness.conversation.jumpToBottom()
        harness.pump(for: 0.03) // far less than the 0.2 s glide
        let last = try frame(harness, "$j40")
        XCTAssertEqual(last.maxY, 400 - ConversationView.timelineVerticalPadding - 0.5, accuracy: 2.0, "already at the bottom")
    }

    // MARK: - Item 8: No Jump on Sending -> Sent

    private func message(_ id: String, _ status: EventStatus, ts: Int) -> Event {
        Fixture.text(id, "Message \(id)", mine: true, ts: ts, status: status)
    }

    private func setItems(_ harness: TableHarness, _ events: [Event], receipt: String?) {
        harness.conversation.setSnapshotStateForTesting(
            roomID: "!motion-view-test",
            items: Fixture.items(events),
            row: Fixture.row("!motion-view-test", "Motion Chat", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features,
            lastOutgoingID: receipt
        )
        harness.pump(for: 0.15)
    }

    private func frame(_ harness: TableHarness, _ id: String) throws -> CGRect {
        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == id })
        return harness.host.convert(harness.tableView.rect(ofRow: row), from: harness.tableView)
    }

    /// The newest bubble stays exactly where it is when Sending becomes Sent.
    func testSendingToSentKeepsTheNewestBubbleWhereItIs() throws {
        let older = message("$older", .sent, ts: 10)
        let harness = try mountTable(
            items: Fixture.items([older, message("$newest", .pending, ts: 2)]),
            lastOutgoingID: "$older", size: NSSize(width: 600, height: 400)
        )
        defer { harness.tearDown() }
        let sendingFrame = try frame(harness, "$newest")

        setItems(harness, [older, message("$newest", .sent, ts: 2)], receipt: "$newest")
        let sentFrame = try frame(harness, "$newest")
        XCTAssertEqual(sentFrame.minY, sendingFrame.minY, accuracy: 0.5, "the newest bubble does not jump")
        XCTAssertEqual(sentFrame.height, sendingFrame.height, accuracy: 0.5, "Sending and Sent are the same height")
    }

    /// The receipt line sits under the earlier message while a newer one is held, sending or fails. Starting a send
    /// or failing one never changes the earlier message's row (the 19 pt the QA review claimed).
    func testStartingOrFailingASendNeverShiftsTheReceiptLine() throws {
        let older = message("$older", .sent, ts: 10)
        let harness = try mountTable(items: Fixture.items([older]), lastOutgoingID: "$older",
                                     size: NSSize(width: 600, height: 400))
        defer { harness.tearDown() }
        let withReceipt = try frame(harness, "$older")

        for state in [EventStatus.queued, .pending, .waiting, .failed] {
            setItems(harness, [older, message("$newest", state, ts: 2)], receipt: "$older")
            let now = try frame(harness, "$older")
            XCTAssertEqual(now.height, withReceipt.height, accuracy: 0.5,
                           "$older keeps its receipt line (same height) while the newer message is \(state.rawValue)")
            XCTAssertEqual(try frame(harness, "$newest").minY, now.maxY, accuracy: 0.5, "no gap opens between them")
        }
    }

    /// Where the top edge of a row actually is on screen at this instant (the layer as drawn, mid-animation included),
    /// in the window's y-up space: bigger is higher.
    private func visualTop(_ harness: TableHarness, _ id: String) throws -> CGFloat {
        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == id })
        let rowLayer = try XCTUnwrap(harness.tableView.rowView(atRow: row, makeIfNecessary: false)?.layer)
        var root = rowLayer
        while let up = root.superlayer { root = up }
        let drawn = rowLayer.presentation() ?? rowLayer
        let rootDrawn = root.presentation() ?? root
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: drawn.bounds.height)]
        return corners.map { drawn.convert($0, to: rootDrawn).y }.max() ?? 0
    }

    private func sendingBecomesSent(reduceMotion: Bool) throws -> (newest: [CGFloat], older: [CGFloat], shift: CGFloat) {
        let older = message("$older", .sent, ts: 10)
        let harness = try mountTable(
            items: Fixture.items([older, message("$newest", .pending, ts: 2)]),
            lastOutgoingID: "$older", size: NSSize(width: 600, height: 400)
        )
        defer { harness.tearDown() }
        harness.coordinator.reduceMotionOverrideForTesting = reduceMotion
        harness.bottomInsetBox.bottomSafeAreaInset = 0.5 // hands the coordinator the setting
        harness.pump(for: 0.1)
        let newestBefore = try visualTop(harness, "$newest")
        let olderBefore = try visualTop(harness, "$older")
        let olderHeightBefore = try frame(harness, "$older").height

        harness.conversation.setSnapshotStateForTesting(
            roomID: "!motion-view-test",
            items: Fixture.items([older, message("$newest", .sent, ts: 2)]),
            row: Fixture.row("!motion-view-test", "Motion Chat", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features,
            lastOutgoingID: "$newest"
        )
        var newest: [CGFloat] = [], olderShift: [CGFloat] = []
        for _ in 0 ..< 14 {
            harness.pump(for: 0.02)
            newest.append(try visualTop(harness, "$newest") - newestBefore)
            olderShift.append(olderBefore - (try visualTop(harness, "$older")))
        }
        let olderHeightAfter = try frame(harness, "$older").height
        return (newest, olderShift, olderHeightBefore - olderHeightAfter)
    }

    /// Mounted, measured on screen at every step: the newest bubble does not move at any moment of Sending -> Sent;
    /// the older message loses its "Sent" line over 0.15 s (its rows ease down by the line's height), not at once.
    func testTheNewestBubbleNeverMovesAndTheReceiptLineEasesAway() throws {
        let run = try sendingBecomesSent(reduceMotion: false)
        XCTAssertGreaterThan(run.shift, 10, "the older message lost its receipt line")
        for (step, moved) in run.newest.enumerated() {
            XCTAssertEqual(moved, 0, accuracy: 0.6, "the newest bubble moved at step \(step)")
        }
        XCTAssertEqual(run.older.last ?? 0, run.shift, accuracy: 1.0, "the older rows end where the line's height puts them")
        XCTAssertLessThan(run.older.first ?? run.shift, run.shift - 3, "eased: not already there after 20 ms")
        XCTAssertEqual(run.older, run.older.sorted(), "and it only ever moves one way")
    }

    /// Under Reduce Motion the same change is instant: no frame of it is in between.
    func testTheReceiptLineGoesAtOnceUnderReduceMotion() throws {
        let run = try sendingBecomesSent(reduceMotion: true)
        for moved in run.newest { XCTAssertEqual(moved, 0, accuracy: 0.6) }
        XCTAssertEqual(run.older.first ?? 0, run.shift, accuracy: 1.0, "already there: no ease")
    }

    // MARK: - Mounted: the placeholder, the jump button and the highlight tint under Reduce Motion

    private func mount<V: View>(_ view: V, size: NSSize = NSSize(width: 500, height: 300)) -> (host: NSHostingView<V>, window: NSWindow) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        return (host, window)
    }

    private func pumpRunLoop(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    /// The strongest alpha anywhere in what the view draws.
    private func peakAlpha(_ host: NSView) -> CGFloat {
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        var peak: CGFloat = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                peak = max(peak, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        return peak
    }

    /// Nothing for the first 120 ms; then the message-shaped bars fade in over 0.2 s, or just appear under Reduce Motion.
    func testThePlaceholderIsPlainFor120msThenFadesInOrJustAppearsUnderReduceMotion() {
        let normal = mount(TimelinePlaceholder(reduceMotionOverride: false))
        defer { normal.window.orderOut(nil) }
        let reduced = mount(TimelinePlaceholder(reduceMotionOverride: true))
        defer { reduced.window.orderOut(nil) }

        pumpRunLoop(0.05)
        XCTAssertEqual(peakAlpha(normal.host), 0, accuracy: 0.001, "plain at 50 ms")
        XCTAssertEqual(peakAlpha(reduced.host), 0, accuracy: 0.001, "plain at 50 ms")

        pumpRunLoop(0.12) // about 170 ms: the delay is over, the fade has begun
        let atReduced = peakAlpha(reduced.host)
        XCTAssertGreaterThan(atReduced, 0.03, "Reduce Motion: there at once, in full")
        XCTAssertLessThan(peakAlpha(normal.host), atReduced - 0.005, "otherwise still fading in")

        pumpRunLoop(0.4)
        XCTAssertEqual(peakAlpha(normal.host), atReduced, accuracy: 0.01, "it ends at the same strength")
    }

    /// The width of the jump button, measured as drawn, over the jump from a search result: it does not snap.
    func testTheJumpButtonKeepsItsWidthWhenAJumpFromASearchWindowEndsAway() throws {
        _ = NSApplication.shared
        let box = try mountTable(items: Fixture.items([Fixture.text("$x", "x", mine: false, ts: 1)]))
        let conversation = box.conversation
        box.tearDown()
        conversation.setAwayFromLatestForTesting(true)
        conversation.setBottomStateForTesting(isAtBottom: false)
        let view = JumpToLatestButton(conversation: conversation, bottom: conversation.bottom, appearance: nil,
                                      reduceMotionOverride: false)
        let mounted = mount(view, size: NSSize(width: 500, height: 100))
        defer { mounted.window.orderOut(nil) }
        pumpRunLoop(0.1)
        let awayWidth = mounted.host.fittingSize.width
        XCTAssertGreaterThan(awayWidth, 120, "says \"Jump to latest\"")

        // The jump: away ends at once; the view is not at the bottom yet.
        conversation.setAwayFromLatestForTesting(false)
        pumpRunLoop(0.05)
        XCTAssertEqual(mounted.host.fittingSize.width, awayWidth, accuracy: 0.5, "no snap to the chevron alone")

        // The bottom is reached and the button fades out: still the same width.
        conversation.setBottomStateForTesting(isAtBottom: true)
        pumpRunLoop(0.05)
        XCTAssertEqual(mounted.host.fittingSize.width, awayWidth, accuracy: 0.5, "nor while it fades away")

        // Shown again later by scrolling up: its own, plain label, not the old words.
        pumpRunLoop(0.3)
        conversation.setBottomStateForTesting(isAtBottom: false)
        pumpRunLoop(0.1)
        XCTAssertLessThan(mounted.host.fittingSize.width, awayWidth - 40, "a plain chevron again")
    }

    /// The tint behind a jumped-to message: ramps in normally, is at its peak at once under Reduce Motion.
    func testTheJumpHighlightRampsInNormallyAndIsAtOnceUnderReduceMotion() {
        func tint(reduceMotion: Bool) -> (host: NSHostingView<some View>, window: NSWindow) {
            mount(JumpHighlightTint(isHighlighted: true, rowID: "$m", reduceMotionOverride: reduceMotion), size: NSSize(width: 200, height: 60))
        }
        let normal = tint(reduceMotion: false)
        let reduced = tint(reduceMotion: true)
        defer { normal.window.orderOut(nil); reduced.window.orderOut(nil) }
        pumpRunLoop(0.05)
        let peak = peakAlpha(reduced.host)
        XCTAssertEqual(peak, JumpHighlightMotion.peakTintOpacity, accuracy: 0.02, "Reduce Motion: 40% of the tint, at once")
        XCTAssertLessThan(peakAlpha(normal.host), peak - 0.02, "otherwise it has barely begun at 50 ms")
        pumpRunLoop(0.27) // 0.32 s: the peak, as the fade out is only beginning
        XCTAssertEqual(peakAlpha(normal.host), peak, accuracy: 0.03, "and reaches the same peak")
        pumpRunLoop(0.2)
        pumpRunLoop(1.3)
        XCTAssertLessThan(peakAlpha(normal.host), 0.02, "then fades away over the rest of 1.5 s")
        XCTAssertEqual(peakAlpha(reduced.host), peak, accuracy: 0.02, "Reduce Motion: stays until the model clears it")
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
        let rowsBefore = try XCTUnwrap(harness.host.first(TimelineNSTableView.self)).numberOfRows
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(manyOlder + twoOlder + events))
        // The moment the rows are in, not after a settle: a jump that is pulled back later is still a jump on screen.
        let arrival = Date()
        while try XCTUnwrap(harness.host.first(TimelineNSTableView.self)).numberOfRows == rowsBefore,
              Date().timeIntervalSince(arrival) < 2 {
            harness.pump(for: 0.005)
        }
        XCTAssertEqual(
            try rowFrameInHost("$s1").minY, beforeTallPrependS1MinY, accuracy: 2.0,
            "older messages arriving keep existing rows where they are, from the first moment"
        )
        harness.pump(for: 0.2)
        XCTAssertEqual(
            try rowFrameInHost("$s1").minY, beforeTallPrependS1MinY, accuracy: 2.0,
            "crossing from short to tall keeps existing rows stationary without bounce"
        )
    }

    // MARK: - Item 9: A chat that fills the pane stays at the bottom when the pane shrinks

    /// Without Liquid Glass the composer takes room from the timeline, so the timeline itself gets shorter. The
    /// newest message must stay in view at once, not 150 ms later (this fails on the old ordering, which read "at the
    /// bottom" after the resize had already moved the clip view).
    func testATallChatStaysAtTheBottomAtOnceWhenThePaneShrinks() throws {
        let harness = try mountTable(items: fullPage(), size: NSSize(width: 700, height: 600))
        defer { harness.tearDown() }
        let newest = try frame(harness, "$p50")
        XCTAssertEqual(newest.maxY, 600 - ConversationView.timelineVerticalPadding, accuracy: 2.0)

        // The width changes with the height, as it does when the window is dragged by its corner.
        for (width, height) in [(CGFloat(690), CGFloat(560)), (680, 500), (670, 440)] {
            let size = NSSize(width: width, height: height)
            harness.window.setContentSize(size)
            harness.host.frame = NSRect(origin: .zero, size: size)
            harness.host.layoutSubtreeIfNeeded()
            harness.pump(for: 0.03) // well under the 150 ms the timeline once took to notice
            XCTAssertEqual(try frame(harness, "$p50").maxY, height - ConversationView.timelineVerticalPadding, accuracy: 2.0,
                           "still at the bottom at \(height) pt")
            XCTAssertTrue(harness.conversation.isAtBottom)
        }
    }

    /// The bottom inset grows and shrinks (the composer, a typing line that eases in and out): each step keeps the
    /// newest message flush above it, and a shrink is not mistaken for the person scrolling up.
    func testATallChatStaysAtTheBottomWhileTheBottomInsetEasesUpAndDown() throws {
        let harness = try mountTable(items: fullPage(), size: NSSize(width: 700, height: 600))
        defer { harness.tearDown() }
        let steps: [CGFloat] = [8, 20, 34, 48, 62, 76, 62, 48, 34, 20, 8, 0]
        for inset in steps {
            harness.bottomInsetBox.bottomSafeAreaInset = inset
            harness.pump(for: 0.03)
            XCTAssertEqual(
                try frame(harness, "$p50").maxY, 600 - inset - ConversationView.timelineVerticalPadding, accuracy: 2.0,
                "flush above an inset of \(inset)"
            )
        }
        XCTAssertTrue(harness.conversation.isAtBottom)
        // A message arriving after the shrink still follows the bottom (pinning was not cancelled).
        var events = fullPageEvents()
        events.append(Fixture.text("$p51", "One more", mine: false, ts: 1))
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(events))
        harness.pump(for: 0.15)
        XCTAssertEqual(try frame(harness, "$p51").maxY, 600 - ConversationView.timelineVerticalPadding, accuracy: 2.0)
    }

    // MARK: - Item 20: Highlight Duration

    func testJumpHighlightDurationIsOneAndAHalfSeconds() {
        XCTAssertEqual(ConversationModel.highlightDuration, .milliseconds(1500))
    }
}
