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
        let style = RowStyle(InboxPreferences(defaults: defaults()))
        let rows = [
            Fixture.row("!1", "Eddie Stecker, Kent Hua, GitHub", network: "slack", direct: false, ts: 5,
                        preview: "Merged the pull request for the new pipeline and the deploy is now running", unread: 3),
            Fixture.row("!2", "#data-science", network: "slack", direct: false, ts: 60 * 30,
                        preview: "Model eval finished. Accuracy is up two points on the holdout set."),
            Fixture.row("!3", "#general", network: "slack", direct: false, ts: 60 * 40, preview: "Lunch at noon?"),
            Fixture.row("!4", "Ann & Bo", network: "whatsapp", direct: false, ts: 60 * 26,
                        preview: "See you there", mine: true, status: .seen),
            Fixture.row("!5", "Weekend Hikers", network: "signal", direct: false, ts: 60 * 24 * 3, preview: "Who has the map?"),
            Fixture.row("!6", "Ann Example", network: "telegram", ts: 60 * 24 * 20, preview: "Thanks!"),
            Fixture.row("!7", "Dee Example", network: "imessage", ts: 60 * 24 * 500, preview: "Happy new year"),
            threadRow("!8", "Ann Example", direct: true, mine: false, preview: "Can you look at this thread?"),
            threadRow("!9", "Dev Chat, Ops Chat", direct: false, mine: true, preview: "Replying inside the thread"),
        ]
        check(try Snapshot.render("inbox-refresh-rows", width: 340) {
            VStack(spacing: 0) {
                ForEach(rows, id: \.roomID) { row in
                    InboxRowView(row: row, networkName: row.network, now: Fixture.now, style: style,
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
                    InboxRowView(row: row, networkName: row.network, now: Fixture.now, style: compact,
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

    private func check(_ sizes: [NSSize], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sizes.count, 2, file: file, line: line)
        for size in sizes { XCTAssertGreaterThan(size.height, 10, file: file, line: line) }
    }
}
