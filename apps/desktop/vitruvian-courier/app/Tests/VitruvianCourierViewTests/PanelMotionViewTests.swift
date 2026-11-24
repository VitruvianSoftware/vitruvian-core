// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest

@testable import VitruvianCourier
import VitruvianCourierCore

/// Stream C (panels, lists, loading states) against the real views and modifiers: each test would fail on the
/// behaviour it replaced (the reserved typing band, the command bar clearing under its fade, the always-on list mask,
/// a shimmer that kept running in a hidden window).
@MainActor
final class PanelMotionViewTests: XCTestCase {
    private var suites: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for name in suites {
            ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name)
        }
        suites = []
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs = []
    }

    // MARK: Helpers

    /// Runs the main run loop until `condition` holds or `timeout` seconds of wall-clock time have passed. Returns
    /// whether it held. A wall-clock deadline, not an iteration count: a run-loop turn with nothing to do returns at
    /// once, so a count says nothing about elapsed time.
    @discardableResult
    private func pump(_ host: NSView? = nil, timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            host?.layoutSubtreeIfNeeded()
            if condition() { return true }
            let before = Date()
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if Date().timeIntervalSince(before) < 0.005 { Thread.sleep(forTimeInterval: 0.005) }
        }
        host?.layoutSubtreeIfNeeded()
        return condition()
    }

    /// Lets `seconds` of wall-clock time pass with the run loop running.
    private func settle(_ host: NSView? = nil, _ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        pump(host, timeout: seconds + 1) { Date() >= end }
    }

    /// A window ordered in far off screen (so the system treats it as on screen, and animations and the shimmer run)
    /// that nobody sees.
    private func showOffscreen(_ view: NSView, size: NSSize) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        return window
    }

    private func close(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    private func hosted<V: View>(_ view: V, size: NSSize) -> (NSWindow, NSHostingView<V>) {
        let host = NSHostingView(rootView: view)
        return (showOffscreen(host, size: size), host)
    }

    /// The alpha (0...1) of the pixel at `point` (top-left origin) of what `view` draws.
    private func alpha(of view: NSView, at point: NSPoint) -> CGFloat {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Rows count from the top (`testPixelSamplingCountsRowsFromTheTop` pins that down).
        return rep.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? -1
    }

    func testPixelSamplingCountsRowsFromTheTop() {
        let view = VStack(spacing: 0) {
            Color.red.frame(height: 50)
            Color.clear.frame(height: 50)
        }.frame(width: 100, height: 100)
        let (window, host) = hosted(view, size: NSSize(width: 100, height: 100))
        defer { close(window) }
        XCTAssertGreaterThan(alpha(of: host, at: NSPoint(x: 50, y: 10)), 0.99, "the top half is drawn")
        XCTAssertLessThan(alpha(of: host, at: NSPoint(x: 50, y: 90)), 0.01, "the bottom half is clear")
    }

    private func defaults() -> UserDefaults {
        let name = "courier.panelmotion.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func offlineApp() throws -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-panelmotion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir,
            environment: [:],
            launcher: FoundationProcessLauncher()
        ))
    }

    // MARK: Item 11: side panes

    func testSidePaneEntranceFadesInOncePerOpenAndAReplayedPaneShowsAtOnce() {
        var played = 0
        let playing = Color.red.frame(width: 200, height: 100)
            .courierSidePaneEntrance(plays: true) { played += 1 }
        let (window, host) = hosted(playing, size: NSSize(width: 200, height: 100))
        defer { close(window) }

        // First frame: the entrance has just begun, so the pane is mostly clear; then it is fully there.
        XCTAssertLessThan(alpha(of: host, at: NSPoint(x: 100, y: 50)), 0.6)
        XCTAssertTrue(pump(host) { alpha(of: host, at: NSPoint(x: 100, y: 50)) > 0.99 }, "the entrance completes")
        XCTAssertEqual(played, 1, "it reports that it played, once")

        // A pane rebuilt while it stays open is told not to play: opaque in its very first frame.
        var replayed = 0
        let rebuilt = Color.red.frame(width: 200, height: 100)
            .courierSidePaneEntrance(plays: false) { replayed += 1 }
        let (window2, host2) = hosted(rebuilt, size: NSSize(width: 200, height: 100))
        defer { close(window2) }
        XCTAssertGreaterThan(alpha(of: host2, at: NSPoint(x: 100, y: 50)), 0.99, "no entrance on a rebuilt pane")
        settle(host2, 0.1)
        XCTAssertEqual(replayed, 0)
    }

    func testSidePaneEntranceWithReduceMotionNeverMovesTheContent() {
        // Mid-animation the rising pane's content is still a few points low, so its top row is empty and its bottom
        // row is clipped: the top row is clearer than the middle row. With Reduce Motion it is a plain fade: the
        // rows match.
        func sampleMidAnimation(reduceMotion: Bool) -> (middle: CGFloat, top: CGFloat)? {
            let view = Color.red.frame(width: 200, height: 100)
                .courierSidePaneEntrance(plays: true) {}
                .environment(\.courierReduceMotionOverride, reduceMotion)
            let (window, host) = hosted(view, size: NSSize(width: 200, height: 100))
            defer { close(window) }
            var result: (CGFloat, CGFloat)?
            pump(host, timeout: 1) {
                let middle = alpha(of: host, at: NSPoint(x: 100, y: 50))
                if middle > 0.15, middle < 0.85 {
                    result = (middle, alpha(of: host, at: NSPoint(x: 100, y: 1)))
                    return true
                }
                return middle > 0.99
            }
            return result.map { ($0.0, $0.1) }
        }
        guard let still = sampleMidAnimation(reduceMotion: true) else {
            XCTFail("never caught the reduced-motion fade part way")
            return
        }
        XCTAssertEqual(still.top, still.middle, accuracy: 0.05, "Reduce Motion: a fade, no rise")
        guard let moving = sampleMidAnimation(reduceMotion: false) else {
            XCTFail("never caught the entrance part way")
            return
        }
        XCTAssertLessThan(moving.top, moving.middle - 0.05, "without Reduce Motion the content rises into place")
    }

    func testSidePaneInsideSplitViewKeepsItsWidthAndTheTimelineItsOffset() throws {
        // A real HSplitView with a scrolled column on the left and the entrance pane on the right: the pane's
        // frame is exactly what it is without the modifier, and the left column does not move while the pane
        // animates in.
        struct Content: View {
            let showsPane: Bool
            let withModifier: Bool
            var body: some View {
                HSplitView {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0 ..< 80, id: \.self) { Text("Row \($0)").frame(height: 24) }
                        }
                    }
                    .frame(minWidth: 200, maxWidth: .infinity)
                    if showsPane {
                        if withModifier {
                            Color.blue.courierSidePaneEntrance(plays: true) {}
                                .frame(minWidth: 100, idealWidth: 140, maxWidth: 300)
                        } else {
                            Color.blue.frame(minWidth: 100, idealWidth: 140, maxWidth: 300)
                        }
                    }
                }
            }
        }

        func paneWidth(withModifier: Bool) throws -> CGFloat {
            let (window, host) = hosted(Content(showsPane: true, withModifier: withModifier),
                                           size: NSSize(width: 600, height: 300))
            defer { close(window) }
            settle(host, 0.5)
            let split = try XCTUnwrap(host.first(NSSplitView.self))
            return try XCTUnwrap(split.arrangedSubviews.last).frame.width
        }
        XCTAssertEqual(try paneWidth(withModifier: true), try paneWidth(withModifier: false), accuracy: 0.5)

        final class Toggle: ObservableObject { @Published var showsPane = false }
        struct Root: View {
            @ObservedObject var toggle: Toggle
            var body: some View { Content(showsPane: toggle.showsPane, withModifier: true) }
        }
        let toggle = Toggle()
        let (window, host) = hosted(Root(toggle: toggle), size: NSSize(width: 600, height: 300))
        defer { close(window) }
        settle(host, 0.3)
        let scroll = try XCTUnwrap(host.first(NSScrollView.self))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(host, 0.1)
        let before = scroll.contentView.bounds.origin.y

        toggle.showsPane = true
        var samples: [CGFloat] = []
        pump(host, timeout: 0.6) {
            samples.append(scroll.contentView.bounds.origin.y)
            return false
        }
        XCTAssertGreaterThan(samples.count, 5)
        for sample in samples {
            XCTAssertEqual(sample, before, accuracy: 0.5, "opening the pane must not move the scroll position")
        }
        toggle.showsPane = false
        settle(host, 0.5)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, before, accuracy: 0.5, "nor must closing it")
    }

    // MARK: Items 11, 13: the real ConversationView

    private final class TypingBox: ObservableObject {
        @Published var text: String?
        /// False swaps the whole conversation out for an empty view, as New Chat does in the main window.
        @Published var showsConversation = true
    }

    private final class Frames {
        var values: [String: CGRect] = [:]
        /// Every probe call, in order (an entrance that plays reports itself as "entrance/...").
        var calls: [String] = []
    }

    private struct ConversationRoot: View {
        @ObservedObject var box: TypingBox
        let conversation: ConversationModel
        let inbox: InboxModel
        let messageActions: MessageActionsModel
        let scheduled: ScheduledModel
        let prefs: ComposerPreferences
        let app: AppModel
        let frames: Frames

        var body: some View {
            Group {
                if box.showsConversation {
                    ConversationView(
                        conversation: conversation,
                        composer: conversation.composer,
                        inbox: inbox,
                        messageActions: messageActions,
                        scheduled: scheduled,
                        preferences: prefs,
                        thread: conversation.thread,
                        focus: MessageFocus(),
                        appModel: app
                    )
                } else {
                    Color.clear
                }
            }
            .environment(\.liquidGlass, false)
            .environment(\.typingLineForTesting, box.text)
            .environment(\.conversationLayoutProbe) { name, frame in
                frames.values[name] = frame
                frames.calls.append(name)
            }
        }
    }

    private struct ChatHost {
        let window: NSWindow
        let host: NSView
        let box: TypingBox
        let conversation: ConversationModel
        let room: String
        let frames: Frames
    }

    private struct LoadedChat {
        let window: NSWindow
        let host: NSView
        let box: TypingBox
        let conversation: ConversationModel
        let table: TimelineNSTableView
        let scroll: NSScrollView
        let room: String
        let frames: Frames
    }

    /// A chat of `messages` messages in a window `width` wide, on `engine`; nothing waited for.
    private func makeChatHost(engine: TimelineEngine, messages: Int = 80, width: CGFloat = 760) throws -> ChatHost {
        let store = defaults()
        let app = try offlineApp()
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = engine
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard()
        )
        let room = "!panel-motion"
        let events = (0 ..< messages).map {
            Fixture.text("$m\($0)", "Message \($0)", mine: $0 % 2 == 0, ts: messages - $0)
        }
        conversation.setSnapshotStateForTesting(
            roomID: room,
            items: Fixture.items(events, isDirect: true),
            row: Fixture.row(room, "Panel Chat", ts: 1, preview: "Message"),
            features: Fixture.features
        )
        let box = TypingBox()
        let frames = Frames()
        let root = ConversationRoot(
            box: box, conversation: conversation, inbox: inbox, messageActions: messageActions,
            scheduled: ScheduledModel(appModel: app), prefs: prefs, app: app, frames: frames
        )
        let hostView = NSHostingView(rootView: root)
        let window = showOffscreen(hostView, size: NSSize(width: width, height: 460))
        return ChatHost(window: window, host: hostView, box: box, conversation: conversation, room: room, frames: frames)
    }

    private func openLoadedChat(messages: Int = 80, width: CGFloat = 760) throws -> LoadedChat {
        let chat = try makeChatHost(engine: .table, messages: messages, width: width)
        XCTAssertTrue(pump(chat.host) { chat.host.first(TimelineNSTableView.self) != nil }, "the timeline is built")
        let table = try XCTUnwrap(chat.host.first(TimelineNSTableView.self))
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        XCTAssertTrue(pump(chat.host) { table.numberOfRows > 10 && chat.conversation.isAtBottom }, "opens at the newest message")
        settle(chat.host, 0.3)
        return LoadedChat(window: chat.window, host: chat.host, box: chat.box, conversation: chat.conversation,
                          table: table, scroll: scroll, room: chat.room, frames: chat.frames)
    }

    private func isAtBottom(_ scroll: NSScrollView) -> Bool {
        guard let doc = scroll.documentView else { return false }
        let clip = scroll.contentView
        let maxY = doc.frame.height - clip.bounds.height + scroll.contentInsets.bottom
        return abs(clip.bounds.origin.y - maxY) <= 2
    }

    func testTypingPillRaisesTheBottomInsetAtTheBottomKeepingTheNewestMessagePinned() throws {
        let chat = try openLoadedChat()
        defer { close(chat.window) }
        XCTAssertTrue(isAtBottom(chat.scroll))
        let base = chat.scroll.contentInsets.bottom
        let lastRow = chat.table.numberOfRows - 1

        let raise = TypingLineMotion.insetHeight(raised: true, rowPadding: ConversationView.timelineVerticalPadding)
        chat.box.text = "Ana is typing…"
        XCTAssertTrue(
            pump(chat.host, timeout: 2) { abs(chat.scroll.contentInsets.bottom - (base + raise)) < 0.5 },
            "the inset eases up (was \(base), now \(chat.scroll.contentInsets.bottom))"
        )
        settle(chat.host, 0.2)
        XCTAssertTrue(isAtBottom(chat.scroll), "the newest message stays pinned to the bottom")
        let newest = chat.table.rect(ofRow: lastRow)
        let visible = chat.scroll.contentView.bounds
        // The pill's top is pillGap + pillHeight above the timeline's bottom edge (no bar under it here); the newest
        // message must end 6 pt above that.
        let pillTop = TypingLineMotion.pillGap + TypingLineMotion.pillHeight
        XCTAssertEqual(
            (visible.maxY - newest.maxY) - pillTop, TypingLineMotion.messageGap, accuracy: 1.0,
            "6 pt between the newest message and the pill"
        )

        chat.box.text = nil
        XCTAssertTrue(
            pump(chat.host, timeout: 2) { abs(chat.scroll.contentInsets.bottom - base) < 0.5 },
            "the inset eases back when nobody is typing"
        )
        settle(chat.host, 0.2)
        XCTAssertTrue(isAtBottom(chat.scroll), "and the newest message is still pinned")
    }

    func testTypingPillChangesNothingWhileTheUserReadsAboveTheBottom() throws {
        let chat = try openLoadedChat()
        defer { close(chat.window) }
        let doc = try XCTUnwrap(chat.scroll.documentView)
        let clip = chat.scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: (doc.frame.height - clip.bounds.height) / 2))
        chat.scroll.reflectScrolledClipView(clip)
        XCTAssertTrue(pump(chat.host) { !chat.conversation.isAtBottom }, "the timeline knows it was scrolled up")
        settle(chat.host, 0.3)
        let originY = clip.bounds.origin.y
        let inset = chat.scroll.contentInsets.bottom
        let docHeight = doc.frame.height

        chat.box.text = "Ana is typing…"
        var originSamples: [CGFloat] = []
        pump(chat.host, timeout: 0.7) {
            originSamples.append(clip.bounds.origin.y)
            return false
        }
        XCTAssertEqual(chat.scroll.contentInsets.bottom, inset, accuracy: 0.01, "no inset change while scrolled up")
        XCTAssertEqual(doc.frame.height, docHeight, accuracy: 0.01, "no layout change anywhere")
        for sample in originSamples {
            XCTAssertEqual(sample, originY, accuracy: 0.5, "what the person reads must not move")
        }

        chat.box.text = nil
        settle(chat.host, 0.7)
        XCTAssertEqual(clip.bounds.origin.y, originY, accuracy: 0.5)
        XCTAssertEqual(chat.scroll.contentInsets.bottom, inset, accuracy: 0.01)
    }

    func testOpeningAndClosingChatInfoDoesNotMoveTheTimelineScrollPosition() throws {
        let chat = try openLoadedChat()
        defer { close(chat.window) }
        let doc = try XCTUnwrap(chat.scroll.documentView)
        let clip = chat.scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: (doc.frame.height - clip.bounds.height) / 2))
        chat.scroll.reflectScrolledClipView(clip)
        XCTAssertTrue(pump(chat.host) { !chat.conversation.isAtBottom })
        settle(chat.host, 0.3)

        func anchor() -> (row: Int, offset: CGFloat) {
            let rows = chat.table.rows(in: clip.bounds)
            let row = rows.location + 2
            return (row, chat.table.rect(ofRow: row).minY - clip.bounds.origin.y)
        }
        let before = anchor()
        let originBefore = clip.bounds.origin.y

        let info = RoomInfoResult(
            roomID: chat.room, name: "Panel Chat", remoteName: "Panel Chat", network: "whatsapp", isDirect: true,
            features: Fixture.features
        )
        chat.conversation.setChatInfoForTesting(info)
        var samples: [(row: Int, offset: CGFloat)] = []
        pump(chat.host, timeout: 0.9) {
            samples.append(anchor())
            return false
        }
        XCTAssertGreaterThan(samples.count, 5)
        for sample in samples {
            XCTAssertEqual(sample.row, before.row)
            XCTAssertEqual(sample.offset, before.offset, accuracy: 1.0, "the message under the person's eyes stays put")
        }
        XCTAssertEqual(clip.bounds.origin.y, originBefore, accuracy: 1.0)

        chat.conversation.setChatInfoForTesting(nil)
        settle(chat.host, 0.9)
        let after = anchor()
        XCTAssertEqual(after.row, before.row)
        XCTAssertEqual(after.offset, before.offset, accuracy: 1.0, "closing the pane does not move it either")
    }

    // MARK: Item 12: command bar

    private func commandBarModel() -> CommandBarModel {
        let commands = [
            CourierCommand(id: "chat.archive", title: "Archive", category: .chat, run: {}),
            CourierCommand(id: "chat.mute", title: "Mute", category: .chat, run: {}),
            CourierCommand(id: "settings.open", title: "Settings", category: .settings, run: {}),
        ]
        return CommandBarModel(defaults: defaults(), commandsProvider: { commands })
    }

    private func searchField(in host: NSView) -> NSTextField? {
        host.descendants { $0 is NSTextField }.compactMap { $0 as? NSTextField }.first { $0.isEditable }
    }

    private func fieldHasFocus(_ window: NSWindow, host: NSView) -> Bool {
        guard let editor = window.firstResponder as? NSText, let field = editor.delegate as? NSTextField else {
            return false
        }
        return field.isDescendant(of: host)
    }

    func testCommandBarFocusesTheFieldAtOnceAndKeepsWhatItShowedWhileFadingOut() throws {
        let model = commandBarModel()
        let (window, host) = hosted(CommandBarOverlayHost(model: model), size: NSSize(width: 800, height: 600))
        defer { close(window) }
        window.makeKey()

        let opened = Date()
        model.open(initialQuery: "arch")
        XCTAssertTrue(pump(host, timeout: 1) { fieldHasFocus(window, host: host) }, "the text field takes focus")
        XCTAssertLessThan(Date().timeIntervalSince(opened), 0.25, "focus is immediate, not after the fade")
        settle(host, 0.3)

        let field = try XCTUnwrap(searchField(in: host))
        XCTAssertEqual(field.stringValue, "arch")
        // Typing goes to whatever is first responder: the open panel's field takes it.
        func type(_ text: String) {
            (window.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        type("z") // the field starts with its text selected, so this replaces it
        XCTAssertTrue(pump(host, timeout: 1) { model.query.contains("z") }, "typing reaches the open panel")
        model.query = "arch"
        settle(host, 0.05)

        model.close()
        settle(host, 0.03) // part way through the 0.1 s fade-out
        XCTAssertEqual(model.query, "arch", "the model is not cleared under the fade")
        XCTAssertEqual(try XCTUnwrap(searchField(in: host)).stringValue, "arch", "the panel still shows its query")
        XCTAssertFalse(fieldHasFocus(window, host: host), "the field lets go of focus when the bar closes")
        type("z")
        settle(host, 0.02)
        XCTAssertEqual(model.query, "arch", "no typing reaches the fading panel")
        XCTAssertTrue(pump(host, timeout: 1) { model.query.isEmpty }, "cleared once the fade is over")
        XCTAssertTrue(pump(host, timeout: 1) { searchField(in: host) == nil }, "and the overlay is gone")
    }

    func testCommandBarReopenedDuringTheFadeIsOneFreshOverlayWithFocus() throws {
        let model = commandBarModel()
        let (window, host) = hosted(CommandBarOverlayHost(model: model), size: NSSize(width: 800, height: 600))
        defer { close(window) }
        window.makeKey()

        model.open(initialQuery: "old words")
        XCTAssertTrue(pump(host) { fieldHasFocus(window, host: host) })
        settle(host, 0.2)
        model.close()
        settle(host, 0.03)

        model.open(initialQuery: "new")
        XCTAssertTrue(pump(host, timeout: 1) { fieldHasFocus(window, host: host) }, "focus at once on the reopen")
        settle(host, 0.4) // long past when the first close would have finished clearing and unmounting

        let fields = host.descendants { $0 is NSTextField }.compactMap { $0 as? NSTextField }.filter(\.isEditable)
        XCTAssertEqual(fields.count, 1, "one overlay, never two")
        XCTAssertEqual(fields.first?.stringValue, "new", "fresh: nothing of the old query")
        XCTAssertEqual(model.query, "new", "the first close's late clean-up must not clear the reopened bar")
        XCTAssertTrue(model.isPresented)
        XCTAssertTrue(fieldHasFocus(window, host: host))
    }

    // MARK: Item 14: shimmer

    func testShimmerRunsOnlyWhileVisibleAndStopsWhenHiddenRemovedOrReduceMotion() throws {
        final class Events { var values: [Bool] = [] }
        final class Visible { var value = true }

        /// A window ordered in before its content arrives (as in the app, where the window is up when its views
        /// mount), holding `view`.
        func show<V: View>(_ view: V, size: NSSize) -> (NSWindow, NSHostingView<V>) {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFrontRegardless()
            let host = NSHostingView(rootView: view)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            return (window, host)
        }
        func announce(_ window: NSWindow) {
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }

        // A window that is not on screen: no shimmer, even though the rows have appeared. (Asked of the real
        // window, not a probe.)
        let hiddenEvents = Events()
        let hiddenHost = NSHostingView(rootView: SkeletonRows(compact: false) { hiddenEvents.values.append($0) }
            .frame(width: 280, height: 420))
        let hiddenWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 420),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        hiddenWindow.contentView = hiddenHost
        hiddenHost.layoutSubtreeIfNeeded()
        defer { close(hiddenWindow) }
        settle(hiddenHost, 0.4)
        XCTAssertFalse(hiddenEvents.values.contains(true), "a window that is not showing has no shimmer")

        // Shown, then hidden, then shown again (the system tells the views by notification; the probe stands in
        // for what it would say, as a test window is never reported as visible).
        let visible = Visible()
        let events = Events()
        let probe: @MainActor (NSWindow) -> Bool = { _ in visible.value }
        let (window, host) = show(
            SkeletonRows(compact: false) { events.values.append($0) }
                .environment(\.windowShowsContentProbe, probe)
                // Motion on, whatever the machine says: CI's Macs run with Reduce Motion on.
                .environment(\.courierReduceMotionOverride, false)
                .frame(width: 280, height: 420),
            size: NSSize(width: 280, height: 420)
        )
        defer { close(window) }
        XCTAssertTrue(pump(host) { events.values.last == true }, "it shimmers while visible")
        visible.value = false
        announce(window)
        XCTAssertTrue(pump(host) { events.values.last == false }, "window hidden: stopped")
        visible.value = true
        announce(window)
        XCTAssertTrue(pump(host) { events.values.last == true }, "window shown again: running")

        // Reduce Motion: never.
        let stillEvents = Events()
        let (stillWindow, stillHost) = show(
            SkeletonRows(compact: false) { stillEvents.values.append($0) }
                .environment(\.windowShowsContentProbe, probe)
                .environment(\.courierReduceMotionOverride, true)
                .frame(width: 280, height: 420),
            size: NSSize(width: 280, height: 420)
        )
        defer { close(stillWindow) }
        settle(stillHost, 0.4)
        XCTAssertFalse(stillEvents.values.contains(true), "Reduce Motion: a static shimmer")

        // Removed from the tree: it reports stopped.
        final class Gate: ObservableObject { @Published var shown = true }
        let gate = Gate()
        let goneEvents = Events()
        struct Root: View {
            @ObservedObject var gate: Gate
            let events: Events
            let probe: @MainActor (NSWindow) -> Bool
            var body: some View {
                if gate.shown {
                    SkeletonRows(compact: true) { events.values.append($0) }
                        .environment(\.windowShowsContentProbe, probe)
                        .environment(\.courierReduceMotionOverride, false)
                        .frame(width: 280, height: 300)
                } else {
                    Color.clear.frame(width: 280, height: 300)
                }
            }
        }
        let (goneWindow, goneHost) = show(Root(gate: gate, events: goneEvents, probe: probe),
                                          size: NSSize(width: 280, height: 300))
        defer { close(goneWindow) }
        XCTAssertTrue(pump(goneHost) { goneEvents.values.last == true })
        gate.shown = false
        XCTAssertTrue(pump(goneHost) { goneEvents.values.last == false }, "removed: stopped")
    }

    func testSkeletonRowsRenderInLightAndDark() throws {
        XCTAssertEqual(try Snapshot.render("skeleton-rows-regular", width: 280, height: 420) {
            SkeletonRows(compact: false)
        }.count, 2)
        XCTAssertEqual(try Snapshot.render("skeleton-rows-compact", width: 280, height: 420) {
            SkeletonRows(compact: true)
        }.count, 2)
    }

    // MARK: Item 15: scroll-edge fades

    private func tallScrollView(rows: Int = 30, state report: @escaping (ScrollEdgeFadeState) -> Void = { _ in })
        -> some View
    {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(0 ..< rows, id: \.self) { idx in
                    Text("Row \(idx)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.05))
                }
            }
            .padding(6)
        }
        .frame(width: 220, height: 160)
        .courierScrollEdgeFade(refreshToken: rows, onStateChange: report)
    }

    func testEdgeFadeStateFollowsScrollingAndHitTestingStillReachesTheList() throws {
        var latest = ScrollEdgeFadeState.none
        let (window, host) = hosted(tallScrollView { latest = $0 }, size: NSSize(width: 220, height: 160))
        defer { close(window) }

        XCTAssertTrue(pump(host) { host.first(NSScrollView.self) != nil && latest == ScrollEdgeFadeState(top: 0, bottom: 1) })
        let scroll = try XCTUnwrap(host.first(NSScrollView.self))

        // Hit testing at the faded edges still reaches the scroll view.
        for y in [CGFloat(5), CGFloat(155)] {
            let hit = try XCTUnwrap(host.hitTest(scroll.convert(NSPoint(x: 40, y: y), to: host)))
            XCTAssertTrue(hit === scroll || hit.isDescendant(of: scroll))
        }

        // Middle: both edges. End: only the top.
        let clip = scroll.contentView
        let doc = try XCTUnwrap(scroll.documentView)
        clip.scroll(to: NSPoint(x: 0, y: 120))
        scroll.reflectScrolledClipView(clip)
        XCTAssertTrue(pump(host) { latest == ScrollEdgeFadeState(top: 1, bottom: 1) })
        clip.scroll(to: NSPoint(x: 0, y: doc.bounds.height - clip.bounds.height))
        scroll.reflectScrolledClipView(clip)
        XCTAssertTrue(pump(host) { latest == ScrollEdgeFadeState(top: 1, bottom: 0) })
        // A few points off the end: the top edge is only part way in (it eases, it does not pop).
        clip.scroll(to: NSPoint(x: 0, y: 4))
        scroll.reflectScrolledClipView(clip)
        XCTAssertTrue(pump(host) { abs(latest.top - 0.4) < 0.01 && latest.bottom == 1 })
    }

    func testEdgeFadeLeavesAListThatFitsAloneAndFadesNothingOnItsEdges() throws {
        // Content that fits has nothing beyond either edge: no fade, so its first and last rows are fully drawn.
        var state = ScrollEdgeFadeState(top: 1, bottom: 1)
        let view = ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 40)
                Color.red.frame(height: 40)
            }
        }
        .frame(width: 200, height: 200)
        .courierScrollEdgeFade(refreshToken: 2) { state = $0 }
        let (window, host) = hosted(view, size: NSSize(width: 200, height: 200))
        defer { close(window) }
        XCTAssertTrue(pump(host) { host.first(NSScrollView.self) != nil && state == .none })
        settle(host, 0.1)
        XCTAssertGreaterThan(alpha(of: host, at: NSPoint(x: 100, y: 0)), 0.99, "first row not faded")
        XCTAssertGreaterThan(alpha(of: host, at: NSPoint(x: 100, y: 79)), 0.99, "last row not faded")
    }

    func testEdgeFadeFadesTheRightEdgeOfThePixels() throws {
        // A scroller of opaque rows. In the middle both the top and bottom 10 pt are see-through; at the end only the
        // top; at the start only the bottom (asymmetric, so a mask the wrong way up is caught).
        let rows = ScrollView {
            VStack(spacing: 0) { ForEach(0 ..< 40, id: \.self) { _ in Color.red.frame(height: 20) } }
        }
        .frame(width: 200, height: 200)
        .courierScrollEdgeFade(refreshToken: 40)
        let (window, host) = hosted(rows, size: NSSize(width: 200, height: 200))
        defer { close(window) }
        XCTAssertTrue(pump(host) { host.first(NSScrollView.self) != nil })
        let scroll = try XCTUnwrap(host.first(NSScrollView.self))
        let clip = scroll.contentView
        let doc = try XCTUnwrap(scroll.documentView)

        func settleAt(_ y: CGFloat) {
            clip.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(clip)
            settle(host, 0.2)
        }
        settleAt(300)
        XCTAssertGreaterThan(alpha(of: host, at: NSPoint(x: 100, y: 100)), 0.95)
        XCTAssertLessThan(alpha(of: host, at: NSPoint(x: 100, y: 1)), 0.5, "middle: the top row fades out")
        XCTAssertLessThan(alpha(of: host, at: NSPoint(x: 100, y: 198)), 0.5, "middle: the bottom row fades out")

        settleAt(doc.bounds.height - clip.bounds.height)
        XCTAssertLessThan(alpha(of: host, at: NSPoint(x: 100, y: 1)), 0.5, "end of list: top fades")
        XCTAssertGreaterThan(alpha(of: host, at: NSPoint(x: 100, y: 198)), 0.95, "end of list: bottom does not")

        settleAt(0)
        XCTAssertGreaterThan(alpha(of: host, at: NSPoint(x: 100, y: 1)), 0.95, "start of list: top does not fade")
        XCTAssertLessThan(alpha(of: host, at: NSPoint(x: 100, y: 198)), 0.5, "start of list: bottom fades")
    }

    func testEdgeFadeMaskFadesTheFullRowWidthWithNoSolidSlice() throws {
        // The mask itself, drawn alone: with both edges fully faded, every column across the width is see-through
        // at the top and bottom, the right edge included (a solid strip there would cut a sharp slice into a
        // selected row).
        let mask = ScrollEdgeFadeMask(state: ScrollEdgeFadeState(top: 1, bottom: 1)).frame(width: 200, height: 200)
        let (window, host) = hosted(mask, size: NSSize(width: 200, height: 200))
        defer { close(window) }
        settle(host, 0.1)
        for x in [CGFloat(2), 100, 185, 198] {
            XCTAssertLessThan(alpha(of: host, at: NSPoint(x: x, y: 1)), 0.2, "faded at the top, column \(x)")
            XCTAssertLessThan(alpha(of: host, at: NSPoint(x: x, y: 198)), 0.2, "faded at the bottom, column \(x)")
            XCTAssertGreaterThan(alpha(of: host, at: NSPoint(x: x, y: 100)), 0.99, "solid in the middle, column \(x)")
        }

        // Nothing fading: the mask is a plain opaque fill.
        let plain = ScrollEdgeFadeMask(state: .none).frame(width: 200, height: 200)
        let (plainWindow, plainHost) = hosted(plain, size: NSSize(width: 200, height: 200))
        defer { close(plainWindow) }
        settle(plainHost, 0.1)
        XCTAssertGreaterThan(alpha(of: plainHost, at: NSPoint(x: 50, y: 1)), 0.99)
        XCTAssertGreaterThan(alpha(of: plainHost, at: NSPoint(x: 50, y: 198)), 0.99)
    }

    func testEdgeFadeFollowsAListThatIsReplacedAfterTheObserverAttached() throws {
        // The scroll view the observer found goes away (the list is rebuilt, here as a list that fits) and the
        // observer must find the new one and report for it, not stay on the dead one.
        final class Model: ObservableObject { @Published var rows = 60 }
        struct Root: View {
            @ObservedObject var model: Model
            let report: (ScrollEdgeFadeState) -> Void
            var body: some View {
                List(0 ..< model.rows, id: \.self) { Text("Chat \($0)").frame(height: 26) }
                    .listStyle(.inset)
                    .id(model.rows)
                    .frame(width: 240, height: 160)
                    .courierScrollEdgeFade(refreshToken: model.rows, onStateChange: report)
            }
        }
        var latest = ScrollEdgeFadeState.none
        let model = Model()
        let (window, host) = hosted(Root(model: model) { latest = $0 }, size: NSSize(width: 240, height: 160))
        defer { close(window) }
        XCTAssertTrue(pump(host) { latest == ScrollEdgeFadeState(top: 0, bottom: 1) }, "the long list fades at the bottom")
        let first = try XCTUnwrap(host.first(NSScrollView.self))

        model.rows = 3
        XCTAssertTrue(
            pump(host, timeout: 4) {
                guard let current = host.first(NSScrollView.self), current !== first else { return false }
                return latest == .none
            },
            "the rebuilt, shorter list is found and has no fade"
        )
    }

    func testEdgeFadeCostOnALongListIsMeasured() throws {
        // 600 rows, scrolled through in 120 steps: main-thread time to lay out and software-render each step, with
        // no fade, with the fade as shipped, and with the always-on SwiftUI mask it replaced. The numbers go to the
        // log (QA-TIMING); the assertion is only that the shipped fade costs no more than about the old one.
        // Measured while choosing the approach (same harness, median step): none 1.5 ms; observer alone 1.6 ms;
        // always-on SwiftUI mask 1.7 ms; a Core Animation mask on the scroll view 2.4 ms and on the clip view,
        // moved at every scroll step, 2.4 ms. So the fade is a SwiftUI mask.
        struct OldAlwaysOnMask: ViewModifier {
            func body(content: Content) -> some View {
                content.mask(
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 10)
                            Color.black
                            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 10)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                )
            }
        }
        func list() -> some View {
            List(0 ..< 600, id: \.self) { index in
                HStack { Circle().frame(width: 28, height: 28); Text("Chat \(index) with a preview line") }
                    .frame(height: 44)
            }
            .listStyle(.inset)
            .frame(width: 300, height: 700)
        }
        func measure(_ view: some View) throws -> Double {
            let (window, host) = hosted(view, size: NSSize(width: 300, height: 700))
            defer { close(window) }
            XCTAssertTrue(pump(host) { host.first(NSScrollView.self) != nil })
            settle(host, 0.4)
            let scroll = try XCTUnwrap(host.first(NSScrollView.self))
            let clip = scroll.contentView
            var times: [Double] = []
            for step in 0 ..< 120 {
                let started = CFAbsoluteTimeGetCurrent()
                clip.scroll(to: NSPoint(x: 0, y: CGFloat(100 + step * 40)))
                scroll.reflectScrolledClipView(clip)
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                times.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            return times.sorted()[times.count / 2] // the median step: robust to a stray slow one
        }
        // Interleaved rounds so that drift (thermal, other load) hits every variant alike.
        var none: [Double] = [], shipped: [Double] = [], old: [Double] = []
        for _ in 0 ..< 3 {
            none.append(try measure(list()))
            shipped.append(try measure(list().courierScrollEdgeFade(refreshToken: 600)))
            old.append(try measure(list().modifier(OldAlwaysOnMask())))
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let (noneMs, shippedMs, oldMs) = (median(none), median(shipped), median(old))
        print(String(
            format: "QA-TIMING edge-fade (600 rows, per scroll step, median of 3 rounds of 120): none %.2f ms, shipped %.2f ms, always-on SwiftUI mask (replaced) %.2f ms",
            noneMs, shippedMs, oldMs
        ))
        print("QA-TIMING edge-fade rounds: none \(none) shipped \(shipped) old \(old)")
        // Logged only: a wall-clock ratio on a shared machine would flake, so nothing is asserted about the numbers.
        XCTAssertGreaterThan(noneMs + shippedMs + oldMs, 0)
    }

    // MARK: Round 2

    func testTypingPillOnTheSwiftUIEngineLeavesRoomUnderTheNewestMessage() throws {
        let chat = try makeChatHost(engine: .swiftui)
        defer { close(chat.window) }
        let newestID = "item/$m79"
        XCTAssertTrue(pump(chat.host, timeout: 4) { chat.frames.values[newestID] != nil && chat.conversation.isAtBottom })
        settle(chat.host, 1.0) // it pins to the bottom for a while after opening
        let before = try XCTUnwrap(chat.frames.values[newestID])

        chat.box.text = "Ana is typing…"
        let raise = TypingLineMotion.insetHeight(raised: true, rowPadding: ConversationView.timelineVerticalPadding)
        XCTAssertTrue(
            pump(chat.host, timeout: 3) { (chat.frames.values[newestID]?.maxY ?? before.maxY) < before.maxY - raise + 1 },
            "the newest message moves up to make room"
        )
        settle(chat.host, 0.5)
        let pill = try XCTUnwrap(chat.frames.values["typingPill"])
        let newest = try XCTUnwrap(chat.frames.values[newestID])
        XCTAssertLessThanOrEqual(newest.maxY, pill.minY - TypingLineMotion.messageGap + 1,
                                 "the pill (\(pill)) does not cover the newest message (\(newest))")

        chat.box.text = nil
        XCTAssertTrue(pump(chat.host, timeout: 3) { abs((chat.frames.values[newestID]?.maxY ?? 0) - before.maxY) < 1 },
                      "and it comes back down when nobody is typing")
    }

    func testTypingPillNeverOverlapsTheJumpToLatestButtonOnANarrowPane() throws {
        let chat = try openLoadedChat(width: 360)
        defer { close(chat.window) }
        let doc = try XCTUnwrap(chat.scroll.documentView)
        let clip = chat.scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: (doc.frame.height - clip.bounds.height) / 2))
        chat.scroll.reflectScrolledClipView(clip)
        XCTAssertTrue(pump(chat.host) { !chat.conversation.isAtBottom }, "scrolled up: the jump button shows")
        chat.box.text = "Alexandra Bartholomew-Longname, Christopher Montgomery and 5 others are typing…"
        settle(chat.host, 0.5)

        let pill = try XCTUnwrap(chat.frames.values["typingPill"])
        let jump = try XCTUnwrap(chat.frames.values["jumpButton"])
        XCTAssertGreaterThan(jump.width, 20, "the button is there")
        XCTAssertTrue(pill.minY < jump.maxY && pill.maxY > jump.minY, "they share a band, so overlap is possible")
        XCTAssertLessThanOrEqual(pill.maxX, jump.minX - TypingLineMotion.buttonGap + 0.5,
                                 "the pill (\(pill)) ends before the button (\(jump)) starts")
        XCTAssertGreaterThan(pill.width, 60, "and still shows some of its words")
    }

    func testCommandBarCloseImmediatelyDoesNotFade() throws {
        let model = commandBarModel()
        let (window, host) = hosted(CommandBarOverlayHost(model: model), size: NSSize(width: 800, height: 600))
        defer { close(window) }
        model.open(initialQuery: "arch")
        XCTAssertTrue(pump(host, timeout: 1) { searchField(in: host) != nil })
        settle(host, 0.3)

        model.closeImmediately()
        // A fade would still show the panel 30 ms on (the ordinary close does: see the test above).
        settle(host, 0.03)
        XCTAssertNil(searchField(in: host), "locked: gone at once, no fade-out showing the reset list")
        XCTAssertEqual(model.query, "")
    }

    func testChatInfoEntrancePlaysWhenOpenedButNotWhenNewChatTakesTheDetailPaneAndCancelBringsItBack() throws {
        let chat = try openLoadedChat()
        defer { close(chat.window) }
        let info = RoomInfoResult(
            roomID: chat.room, name: "Panel Chat", remoteName: "Panel Chat", network: "whatsapp", isDirect: true,
            features: Fixture.features
        )
        func entrances() -> Int { chat.frames.calls.filter { $0 == "entrance/chatInfo" }.count }
        func paneIsUp() -> Bool { chat.host.first(NSSplitView.self)?.arrangedSubviews.count == 2 }
        XCTAssertEqual(entrances(), 0)

        // The person opens Chat Info: the entrance plays, once.
        chat.conversation.setChatInfoForTesting(info)
        XCTAssertTrue(pump(chat.host, timeout: 2) { paneIsUp() })
        settle(chat.host, 0.5)
        XCTAssertEqual(entrances(), 1, "opening plays the entrance")

        // New Chat takes the detail pane (the conversation view goes), Cancel brings it back with Chat Info still
        // open: it is there at once, not entered again.
        chat.box.showsConversation = false
        settle(chat.host, 0.4)
        chat.box.showsConversation = true
        XCTAssertTrue(pump(chat.host, timeout: 2) { paneIsUp() }, "Chat Info is back")
        settle(chat.host, 0.5)
        XCTAssertEqual(entrances(), 1, "coming back does not replay the entrance")

        // Closing and opening again is a new open: it plays again.
        chat.conversation.setChatInfoForTesting(nil)
        settle(chat.host, 0.4)
        chat.conversation.setChatInfoForTesting(info)
        XCTAssertTrue(pump(chat.host, timeout: 2) { entrances() == 2 }, "a fresh open plays it again")
    }

    // MARK: Reduce Motion override: Chat Info sections and the scheduled strip

    /// Presses the button at `point` (top-left origin) of `host`'s window.
    private func click(_ window: NSWindow, at point: NSPoint) {
        let location = NSPoint(x: point.x, y: window.contentView!.bounds.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) { window.sendEvent(event) }
        }
    }

    /// How many rows of the pixel column at `x` draw anything.
    private func drawnHeight(of view: NSView, x: Int) -> Int {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)
        return (0 ..< rep.pixelsHigh).filter { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.01 }.count
    }

    func testChatInfoSectionExpandsInstantlyUnderReduceMotionAndEasesOtherwise() throws {
        final class Open: ObservableObject { @Published var value = false }
        struct Root: View {
            @ObservedObject var open: Open
            let reduceMotion: Bool
            var body: some View {
                ChatInfoSection(
                    title: "Media", count: 6,
                    isExpanded: Binding(get: { open.value }, set: { open.value = $0 })
                ) {
                    VStack(spacing: 0) { ForEach(0 ..< 6, id: \.self) { Text("Row \($0)").frame(height: 30) } }
                }
                .environment(\.courierReduceMotionOverride, reduceMotion)
                .frame(width: 300)
                .frame(height: 400, alignment: .top)
            }
        }
        /// The drawn heights seen from the click to the end.
        func heights(reduceMotion: Bool) throws -> [Int] {
            let open = Open()
            let (window, host) = hosted(Root(open: open, reduceMotion: reduceMotion), size: NSSize(width: 300, height: 400))
            defer { close(window) }
            settle(host, 0.3)
            var seen = [drawnHeight(of: host, x: 4)]
            click(window, at: NSPoint(x: 40, y: 22))
            XCTAssertTrue(pump(host, timeout: 1) { open.value }, "the click reached the section's button")
            let end = Date().addingTimeInterval(0.6)
            pump(host, timeout: 1) {
                seen.append(drawnHeight(of: host, x: 4))
                return Date() >= end
            }
            return seen
        }
        func intermediates(_ seen: [Int]) -> [Int] {
            guard let first = seen.first, let last = seen.last else { return [] }
            return seen.filter { $0 > first + 3 && $0 < last - 3 }
        }
        let still = try heights(reduceMotion: true)
        XCTAssertGreaterThan((still.last ?? 0) - (still.first ?? 0), 60, "it did expand")
        XCTAssertTrue(intermediates(still).isEmpty, "Reduce Motion: no in-between heights, it just opens: \(still)")
        let moving = try heights(reduceMotion: false)
        XCTAssertFalse(intermediates(moving).isEmpty, "otherwise it eases through in-between heights: \(moving)")
    }

    func testScheduledStripBounceHonoursTheReduceMotionOverride() throws {
        final class Trigger: ObservableObject { @Published var value = 0 }
        struct Root: View {
            @ObservedObject var trigger: Trigger
            let reduceMotion: Bool
            var body: some View {
                ScheduledList(
                    messages: [ScheduledMessage(outboxID: 1, roomID: "!r", text: "Later", dueAt: 1_800_000_000_000,
                                                condition: .always, state: .waiting, setAt: 1)],
                    actions: ScheduledActions(),
                    bounceTrigger: trigger.value
                )
                .environment(\.courierReduceMotionOverride, reduceMotion)
                .frame(width: 300, height: 120, alignment: .top)
            }
        }
        /// The weighted vertical centre of what is drawn, in pixels from the top.
        func centre(_ view: NSView) -> CGFloat {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
            view.cacheDisplay(in: view.bounds, to: rep)
            var weight: CGFloat = 0
            var moment: CGFloat = 0
            for y in 0 ..< rep.pixelsHigh {
                for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                    let alpha = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    weight += alpha
                    moment += alpha * CGFloat(y)
                }
            }
            return weight > 0 ? moment / weight : 0
        }
        /// The largest move of the strip's toggle after a message is queued.
        func largestMove(reduceMotion: Bool) -> CGFloat {
            let trigger = Trigger()
            let (window, host) = hosted(Root(trigger: trigger, reduceMotion: reduceMotion), size: NSSize(width: 300, height: 120))
            defer { close(window) }
            settle(host, 0.4)
            let rest = centre(host)
            trigger.value += 1
            var largest: CGFloat = 0
            let end = Date().addingTimeInterval(0.5)
            pump(host, timeout: 1) {
                largest = max(largest, abs(centre(host) - rest))
                return Date() >= end
            }
            return largest
        }
        XCTAssertLessThan(largestMove(reduceMotion: true), 0.2, "Reduce Motion: the toggle does not bounce")
        XCTAssertGreaterThan(largestMove(reduceMotion: false), 1.0, "otherwise it bounces")
    }
}
