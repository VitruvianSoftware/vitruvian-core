// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// The inbox's Beeper-style refresh, drawn light and dark to PNGs for a person to look at: composite group avatars,
/// network tiles, two-line previews with the thread glyph, the pinned tiles, the header buttons, the search chips.
@MainActor
final class InboxVisualRefreshSnapshotTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.refresh.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func offlineApp() -> AppModel {
        AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-snapshots"),
            environment: [:], launcher: FoundationProcessLauncher()))
    }

    private func threadRow(_ id: String, _ name: String, direct: Bool, mine: Bool, preview: String) -> InboxRow {
        InboxRow(roomID: id, network: "slack", name: name, avatarPath: "", isDirect: direct, lastTS: Fixture.millis(30),
                 preview: preview, previewKind: .text, previewMine: mine, unread: 0, muted: false,
                 previewInThread: true)
    }

    func testRowsWithGroupAvatarsAndTwoLinePreviews() throws {
        let app = offlineApp()
        let prefs = InboxPreferences(defaults: defaults())
        let inbox = InboxModel(appModel: app, preferences: prefs)
        let style = RowStyle(prefs)
        let threeMember = Fixture.row(
            "!1",
            "Eddie Stecker, Kent Hua, GitHub",
            network: "slack",
            direct: false,
            ts: 5,
            preview: "Merged the pull request for the new pipeline and the deploy is now running",
            unread: 3,
            memberPreview: [
                RowMember(userID: "@eddie", name: "Eddie Stecker"),
                RowMember(userID: "@kent", name: "Kent Hua"),
                RowMember(userID: "@gh", name: "GitHub"),
            ]
        )
        let fiveMember = Fixture.row(
            "!1b",
            "Eddie Stecker, Kent Hua, GitHub, Alice Smith, Bob Jones",
            network: "slack",
            direct: false,
            ts: 12,
            preview: "All green on main",
            unread: 1
        )
        let customGroup = Fixture.row("!5", "Weekend Hikers", network: "signal", direct: false, ts: 60 * 24 * 3,
                                      preview: "Who has the map?")
        XCTAssertEqual(threeMember.displayTitle, "Eddie, Kent & GitHub")
        XCTAssertEqual(
            fiveMember.displayTitle,
            "Eddie Stecker, Kent Hua, GitHub, Alice Smith, Bob Jones",
            "Without confirmed members, InboxRow.displayTitle leaves the title unchanged"
        )
        inbox.setKnownMembers([
            GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
            GroupTitleMember(userID: "@kent", name: "Kent Hua"),
            GroupTitleMember(userID: "@gh", name: "GitHub", isBot: true),
            GroupTitleMember(userID: "@alice", name: "Alice Smith"),
            GroupTitleMember(userID: "@bob", name: "Bob Jones"),
        ], for: "!1b")
        XCTAssertEqual(inbox.displayTitle(for: fiveMember), "Eddie, Kent, GitHub & 2 others")
        XCTAssertEqual(customGroup.displayTitle, "Weekend Hikers")
        let rows = [
            threeMember,
            fiveMember,
            Fixture.row("!2", "#data-science", network: "slack", direct: false, ts: 60 * 30,
                        preview: "Model eval finished. Accuracy is up two points on the holdout set."),
            Fixture.row("!3", "#general", network: "slack", direct: false, ts: 60 * 40, preview: "Lunch at noon?"),
            Fixture.row("!4", "Ann & Bo", network: "whatsapp", direct: false, ts: 60 * 26,
                        preview: "See you there", mine: true, status: .seen),
            customGroup,
            Fixture.row("!6", "Ann Example", network: "telegram", ts: 60 * 24 * 20, preview: "Thanks!"),
            Fixture.row("!7", "Dee Example", network: "imessage", ts: 60 * 24 * 500, preview: "Happy new year"),
            threadRow("!8", "Ann Example", direct: true, mine: false, preview: "Can you look at this thread?"),
            threadRow("!9", "Dev Chat, Ops Chat", direct: false, mine: true, preview: "Replying inside the thread"),
        ]
        check(try Snapshot.render("inbox-refresh-rows", width: 340) {
            VStack(spacing: 0) {
                ForEach(rows, id: \.roomID) { row in
                    InboxRowView(row: row, displayTitleOverride: inbox.displayTitle(for: row),
                                 networkName: row.network, now: Fixture.now, style: style,
                                 isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {},
                                 decline: {}) { EmptyView() }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                    Divider()
                }
            }
        })
        var compact = style
        compact.compact = true
        check(try Snapshot.render("inbox-refresh-rows-compact", width: 340) {
            VStack(spacing: 0) {
                ForEach(rows.prefix(3), id: \.roomID) { row in
                    InboxRowView(row: row, displayTitleOverride: inbox.displayTitle(for: row),
                                 networkName: row.network, now: Fixture.now, style: compact,
                                 isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {},
                                 decline: {}) { EmptyView() }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }
            }
        })
    }

    func testGroupAvatarSizes() throws {
        let names = ["Eddie Stecker, Kent Hua, GitHub", "Ann & Bo", "#data-science", "#general", "Weekend Hikers"]
        check(try Snapshot.render("group-avatars", width: 360) {
            HStack(spacing: 16) {
                ForEach(names, id: \.self) { name in
                    VStack(spacing: 6) {
                        ChatAvatar(row: Fixture.row("!g", name, direct: false, ts: 1, preview: ""), size: 48)
                            .frame(width: 48, height: 48)
                        ChatAvatar(row: Fixture.row("!g", name, direct: false, ts: 1, preview: ""), size: 28)
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .padding(12)
        })
    }

    func testChannelsAreToldApartByColour() {
        let names = ["#data-science", "#general", "#random", "#eng", "#design"]
        let colours = Set(names.map { GroupCompositeAvatar.channelColor($0).description })
        XCTAssertEqual(colours.count, names.count, "channels get their own colour")
    }

    func testNetworkTilesOnTheRailAndAsBadges() throws {
        check(try Snapshot.render("network-tiles", width: 420) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(NetworkTile.knownNetworks, id: \.self) { NetworkBadge(network: $0, name: $0, size: 26) }
                }
                HStack(spacing: 8) {
                    ForEach(NetworkTile.knownNetworks, id: \.self) {
                        NetworkBadge(network: $0, name: $0, size: 26, tinted: false)
                    }
                }
                HStack(spacing: 14) {
                    ForEach(["slack", "whatsapp", "facebook"], id: \.self) { net in
                        Circle().fill(Color.gray.opacity(0.4)).frame(width: 40, height: 40)
                            .overlay(alignment: .bottomTrailing) {
                                NetworkBadge(network: net, name: net, size: 16, ringed: true).offset(x: 4, y: 4)
                            }
                    }
                }
            }
            .padding(12)
        })
    }

    func testPinnedTiles() throws {
        let rows = [
            Fixture.row("!1", "Eddie Stecker, Kent Hua, GitHub", network: "slack", direct: false, ts: 5, preview: "x", unread: 1),
            Fixture.row("!2", "#data-science", network: "slack", direct: false, ts: 5, preview: "x"),
            Fixture.row("!3", "Ann Example", network: "whatsapp", ts: 5, preview: "x"),
            Fixture.row("!4", "Eddie Stecker", network: "telegram", ts: 5, preview: "x"),
        ]
        check(try Snapshot.render("pinned-tiles", width: 330) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 112), spacing: 6)], spacing: 6) {
                ForEach(rows, id: \.roomID) { row in
                    PinnedChat(row: row, networkName: row.network, isOpen: row.roomID == "!3", isSelected: false,
                               showsBadge: true, tinted: true)
                }
            }
            .padding(10)
        })
    }

    func testHeaderButtons() throws {
        let model = InboxModel(appModel: offlineApp(), preferences: InboxPreferences(defaults: defaults()))
        check(try Snapshot.render("header-buttons", width: 340) {
            HStack(spacing: 8) {
                Text("Inbox").font(.headline)
                Spacer()
                InboxHeaderButtons(inbox: model)
            }
            .padding(10)
        })
    }

    func testSearchChipsAndEmptyInChatState() throws {
        let app = offlineApp()
        let search = SearchModel(appModel: app, recents: RecentSearches(defaults: defaults()), open: { _ in })
        search.filters.chatType = "dm"
        let rows = [
            Fixture.row("!1", "Eddie Stecker, Kent Hua, GitHub", network: "slack", direct: false, ts: 5, preview: "x"),
            Fixture.row("!2", "Ann Example", network: "whatsapp", ts: 6, preview: "x"),
        ]
        check(try Snapshot.render("search-chips-and-empty", width: 560) {
            VStack(alignment: .leading, spacing: 8) {
                SearchFilterBar(search: search, accounts: [])
                SearchNoticeView(notice: .welcomeInChat, clearFilters: {}, retry: {}, scopeName: "Ann Example")
                RecentChatsList(rows: rows) { _ in }
            }
            .padding(14)
        })
    }

    func testConversationHeaderBarHairlineAndTopMessageClearance() throws {
        let store = defaults()
        let app = offlineApp()
        let inboxPreferences = InboxPreferences(defaults: store)
        let composerPreferences = ComposerPreferences(defaults: store)
        let inbox = InboxModel(appModel: app, preferences: inboxPreferences)
        let conversation = ConversationModel(appModel: app, preferences: composerPreferences)
        final class NoPasteboard: TextPasteboard {
            func setString(_: String) {}
        }
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: app,
            preferences: composerPreferences,
            pasteboard: NoPasteboard()
        )
        let scheduled = ScheduledModel(appModel: app)
        let focus = MessageFocus()
        let groupRow = Fixture.row(
            "!grp-header",
            "Eddie Stecker, Kent Hua, GitHub",
            network: "slack",
            direct: false,
            ts: 5,
            preview: "Merged PR #42",
            memberPreview: [
                RowMember(userID: "@eddie", name: "Eddie Stecker"),
                RowMember(userID: "@kent", name: "Kent Hua"),
                RowMember(userID: "@gh", name: "GitHub"),
            ]
        )
        let events = [
            Fixture.text(
                "$k1",
                "First message below the header",
                mine: false,
                ts: 20,
                sender: "@kent:courier.local",
                name: "Kent Hua"
            ),
            Fixture.text("$k2", "Got it, thanks!", mine: true, ts: 10),
        ]
        let items = Fixture.items(events, isDirect: false)
        conversation.setSnapshotStateForTesting(roomID: "!grp-header", items: items, row: groupRow)

        var probedFrames: [String: CGRect] = [:]
        check(try Snapshot.render("conversation-header-clearance", width: 560, height: 280) {
            ConversationView(
                conversation: conversation,
                composer: conversation.composer,
                inbox: inbox,
                messageActions: messageActions,
                scheduled: scheduled,
                preferences: composerPreferences,
                thread: conversation.thread,
                focus: focus,
                appModel: app
            )
            .environment(\.liquidGlass, false)
            .environment(\.conversationLayoutProbe) { name, frame in
                probedFrames[name] = frame
            }
        })

        let headerFrame = try XCTUnwrap(probedFrames["headerOverlay"], "production chatTopHeaderOverlay frame should be reported")
        let firstMessageFrame = try XCTUnwrap(probedFrames["item/$k1"], "first message frame should be reported")
        XCTAssertGreaterThanOrEqual(headerFrame.height, PaneHeaderMetrics.stripHeight)
        XCTAssertGreaterThanOrEqual(
            firstMessageFrame.minY,
            headerFrame.maxY,
            "first message (\(firstMessageFrame)) must start at or below header bottom (\(headerFrame.maxY))"
        )
    }

    func testConversationScrollTargetsLandBelowHeader() throws {
        // Verify normalized anchor math for both top-aligned and centered modes (including tall items).
        let topAnchor = ConversationView.headerClearedScrollAnchor(
            headerInset: 48.5,
            viewportHeight: 220,
            itemHeight: 36,
            preferCenter: false
        )
        XCTAssertEqual(topAnchor.y * (220 - 36), 48.5 + ConversationView.timelineVerticalPadding, accuracy: 0.5)

        let tallAnchor = ConversationView.headerClearedScrollAnchor(
            headerInset: 76,
            viewportHeight: 220,
            itemHeight: 200,
            preferCenter: true
        )
        XCTAssertEqual(tallAnchor.y, 0, "tall items fall back to top alignment rather than extending under the header")

        let store = defaults()
        let app = offlineApp()
        let inboxPreferences = InboxPreferences(defaults: store)
        let composerPreferences = ComposerPreferences(defaults: store)
        let inbox = InboxModel(appModel: app, preferences: inboxPreferences)
        let conversation = ConversationModel(appModel: app, preferences: composerPreferences)
        final class NoPasteboard: TextPasteboard {
            func setString(_: String) {}
        }
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: app,
            preferences: composerPreferences,
            pasteboard: NoPasteboard()
        )
        let scheduled = ScheduledModel(appModel: app)
        let focus = MessageFocus()

        let groupRow = Fixture.row(
            "!grp-scroll",
            "Eddie Stecker, Kent Hua, GitHub",
            network: "slack",
            direct: false,
            ts: 5,
            preview: "Message 20",
            memberPreview: [
                RowMember(userID: "@eddie", name: "Eddie Stecker"),
                RowMember(userID: "@kent", name: "Kent Hua"),
                RowMember(userID: "@gh", name: "GitHub"),
            ]
        )
        let baseEvents: [Event] = (1 ... 20).map { idx in
            let minutesAgo = 40 - idx
            let body = idx == 4
                ? "Unread thread root message #4 with extra context so we can verify clearance"
                : "Conversation message #\(idx)"
            return Fixture.text(
                "$m\(idx)",
                body,
                mine: idx % 2 == 0,
                ts: minutesAgo,
                sender: idx % 2 == 0 ? nil : "@kent:courier.local",
                name: "Kent Hua"
            )
        }
        conversation.setSnapshotStateForTesting(
            roomID: "!grp-scroll",
            items: Fixture.items(baseEvents, isDirect: false),
            row: groupRow,
            hasOlder: true
        )

        var frames: [String: CGRect] = [:]
        let rootView = ConversationView(
            conversation: conversation,
            composer: conversation.composer,
            inbox: inbox,
            messageActions: messageActions,
            scheduled: scheduled,
            preferences: composerPreferences,
            thread: conversation.thread,
            focus: focus,
            appModel: app
        )
        .environment(\.liquidGlass, false)
        .environment(\.conversationLayoutProbe) { name, frame in
            frames[name] = frame
        }

        let size = NSSize(width: 900, height: 280)
        let host = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        func pump(for interval: TimeInterval = 0.08, until condition: (() -> Bool)? = nil) {
            let deadline = Date().addingTimeInterval(interval)
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                host.layoutSubtreeIfNeeded()
                if condition?() == true { break }
            }
        }

        // Wait past startPinningToBottomDuration (1.5 s) so initial pinning finishes cleanly.
        pump(for: 1.7)
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self), "ConversationView must host an NSScrollView")

        // 1. restoreAnchor: scroll to top so ProgressView appears and captures restoreAnchor = "$m1", then prepend older messages.
        for _ in 0 ..< 4 {
            if let docView = scrollView.documentView {
                let docBounds = docView.bounds
                let topPoint = docView.isFlipped
                    ? NSPoint(x: 0, y: docBounds.minY)
                    : NSPoint(x: 0, y: max(docBounds.minY, docBounds.maxY - scrollView.contentView.bounds.height))
                scrollView.contentView.scroll(to: topPoint)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            pump(for: 0.12)
            if frames["item/$m1"] != nil { break }
        }
        conversation.setSnapshotItemsForTesting(Fixture.items(baseEvents, isDirect: false), hasOlder: true)
        pump(for: 0.15)
        let olderEvents: [Event] = (1 ... 5).map { idx in
            Fixture.text(
                "$old\(idx)",
                "Older history message #\(idx)",
                mine: false,
                ts: 100 - idx,
                sender: "@eddie:courier.local",
                name: "Eddie Stecker"
            )
        }
        conversation.setSnapshotItemsForTesting(Fixture.items(olderEvents + baseEvents, isDirect: false), hasOlder: false)
        pump(for: 0.25)

        let baseHeader = try XCTUnwrap(frames["headerOverlay"], "headerOverlay frame must be measured")
        let restoredAnchorFrame = try XCTUnwrap(frames["item/$m1"], "restored anchor message $m1 must be laid out")
        XCTAssertGreaterThanOrEqual(
            restoredAnchorFrame.minY,
            baseHeader.maxY - 0.5,
            "restoreAnchor target ($m1) must land below the header (\(baseHeader.maxY)), got \(restoredAnchorFrame)"
        )
        XCTAssertLessThanOrEqual(
            restoredAnchorFrame.minY,
            baseHeader.maxY + ConversationView.timelineVerticalPadding + 16,
            "restoreAnchor target ($m1) must land near the top below the header, got \(restoredAnchorFrame)"
        )

        // 1b. Older messages that join without a scroll of the person's asking (a page the network answered later, read
        // by `readEarlier`): the model names the message that was first, and the view keeps the person on it. Here
        // there is no older page to ask for (hasOlder is false), so no ProgressView set restoreAnchor.
        for _ in 0 ..< 4 {
            if let docView = scrollView.documentView {
                let docBounds = docView.bounds
                let topPoint = docView.isFlipped
                    ? NSPoint(x: 0, y: docBounds.minY)
                    : NSPoint(x: 0, y: max(docBounds.minY, docBounds.maxY - scrollView.contentView.bounds.height))
                scrollView.contentView.scroll(to: topPoint)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            pump(for: 0.12)
            if frames["item/$old1"] != nil { break }
        }
        let evenOlderEvents: [Event] = (1 ... 5).map { idx in
            Fixture.text(
                "$older\(idx)",
                "Earlier history message #\(idx)",
                mine: false,
                ts: 200 - idx,
                sender: "@eddie:courier.local",
                name: "Eddie Stecker"
            )
        }
        conversation.setEarlierAnchorForTesting("$old1")
        conversation.setSnapshotItemsForTesting(Fixture.items(evenOlderEvents + olderEvents + baseEvents, isDirect: false), hasOlder: false)
        pump(for: 0.25)
        // (ts is minutes ago: 200 is older than everything, so these rows sort above $old1.) The view took the anchor
        // (an unanchored view leaves it for the next taker) and put its message back below the header.
        XCTAssertNil(conversation.takeEarlierAnchor(), "the view must have used the earlier-history anchor")
        let arrivedAnchorFrame = try XCTUnwrap(frames["item/$old1"], "the anchor $old1 must be laid out")
        XCTAssertGreaterThanOrEqual(
            arrivedAnchorFrame.minY, baseHeader.maxY - 0.5,
            "the earlier-history anchor ($old1) must land below the header (\(baseHeader.maxY)), got \(arrivedAnchorFrame)"
        )
        XCTAssertLessThanOrEqual(
            arrivedAnchorFrame.minY, baseHeader.maxY + ConversationView.timelineVerticalPadding + 16,
            "the earlier-history anchor ($old1) must stay near the top below the header, got \(arrivedAnchorFrame)"
        )

        // 2. Jump-to-message (scrollToMessageRequest).
        conversation.scrollToMessageForTesting("$m2")
        pump(for: 0.35)
        let jumpedMessageFrame = try XCTUnwrap(frames["item/$m2"], "jumped message $m2 must be laid out")
        XCTAssertGreaterThanOrEqual(
            jumpedMessageFrame.minY,
            baseHeader.maxY - 0.5,
            "jump-to-message target ($m2) must land below the header (\(baseHeader.maxY)), got \(jumpedMessageFrame)"
        )

        // 3. Jump-to-unread (showNextUnreadThread with ThreadRepliesBanner visible in chatTopHeaderOverlay).
        conversation.setUnreadThreadsForTesting([
            UnreadThread(rootID: "$m4", unread: 2, unreadMentionsMe: false, firstUnreadID: "$r1"),
        ])
        pump(for: 0.15)
        let bannerHeader = try XCTUnwrap(frames["headerOverlay"], "headerOverlay with unread banner must be measured")
        XCTAssertGreaterThan(
            bannerHeader.height,
            PaneHeaderMetrics.stripHeight + 10,
            "ThreadRepliesBanner must enlarge chatTopHeaderOverlay"
        )
        conversation.showNextUnreadThread()
        pump(for: 0.35)
        let unreadRootFrame = try XCTUnwrap(frames["item/$m4"], "unread thread root $m4 must be laid out")
        XCTAssertGreaterThanOrEqual(
            unreadRootFrame.minY,
            bannerHeader.maxY - 0.5,
            "jump-to-unread target ($m4) must land below the header+banner (\(bannerHeader.maxY)), got \(unreadRootFrame)"
        )
    }

    private func check(_ sizes: [NSSize], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sizes.count, 2, file: file, line: line)
        for size in sizes { XCTAssertGreaterThan(size.height, 10, file: file, line: line) }
    }
}
