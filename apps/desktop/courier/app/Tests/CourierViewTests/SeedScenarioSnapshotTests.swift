// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// The group-threads scenario's group chat (the one the test copy opens with `--seed group-threads`), drawn light and
/// dark as seed-group-threads-*.png: the same made-up chat a person sees in the running copy. Like the other
/// snapshots, the asserts check only that it drew, and that the scenario became the timeline it describes.
@MainActor
final class SeedScenarioSnapshotTests: XCTestCase {
    func testGroupThreadsGroupChat() throws {
        let scenario = try SeedScenario.load("group-threads")
        let events = try scenario.events(chat: "grp-launch")
        let messages = Fixture.messages(events)
        // m1…m9: the group's messages outside its two threads.
        XCTAssertEqual(messages.count, 9)
        let roots = events.filter { $0.thread != nil }
        XCTAssertEqual(roots.map { $0.thread?.replies }, [3, 2], "both threads' roots carry their summaries")
        XCTAssertTrue(events.contains { $0.type == "m.reaction" })
        XCTAssertTrue(events.contains { $0.mine })
        XCTAssertTrue(events.contains { $0.senderName == "Ann Example" })

        let ui = MessageUI()
        var actions = Courier.MessageActions(now: { Fixture.now })
        actions.openThread = { _ in }
        let sizes = try Snapshot.render("seed-group-threads", width: 620) {
            VStack(spacing: 0) {
                ForEach(Fixture.items(events)) { item in
                    TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
                }
            }
            .padding(14)
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 100)
            XCTAssertGreaterThan(size.height, 300, "nine messages, not an empty timeline")
        }
    }

    func testMultiNetworkInbox() throws {
        let scenario = try SeedScenario.load("multi-network")
        let rows = scenario.inboxRows()
        XCTAssertEqual(rows.count, 9)
        let general = try XCTUnwrap(rows.first { $0.roomID == "ch-general" })
        XCTAssertTrue(general.previewInThread)
        XCTAssertEqual(general.formattedPreviewText, "You, in a thread: Thanks for the heads up.")

        let suiteName = "courier.seed-inbox.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = ScratchDefaults.suite(named: suiteName)!
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("courier-seed-inbox"),
            environment: [:], launcher: FoundationProcessLauncher()))
        let inboxPrefs = InboxPreferences(defaults: store)
        let inbox = InboxModel(appModel: app, preferences: inboxPrefs)
        inbox.setSnapshotRowsForTesting(rows)
        let lifecycle = SystemLifecycleModel(loginItemService: SnapshotLoginItemService(),
                                             biometricService: SnapshotBiometricService(), defaults: store)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        spaces.setSpacesForTesting([
            Space(spaceID: "inbox", kind: .builtin, title: "Inbox", chats: 9, unreadChats: 5),
            Space(spaceID: "seed-wa", kind: .account, title: "WhatsApp", network: "whatsapp", chats: 3, unreadChats: 2),
            Space(spaceID: "seed-slack", kind: .account, title: "Slack", network: "slack", chats: 3, unreadChats: 2),
            Space(spaceID: "seed-tg", kind: .account, title: "Telegram", network: "telegram", chats: 3, unreadChats: 1),
        ])
        let labels = LabelsModel(appModel: app, lifecycle: lifecycle)
        let style = RowStyle(inboxPrefs)

        let sizes = try Snapshot.render("seed-inbox", width: 400) {
            HStack(alignment: .top, spacing: 0) {
                SpaceBar(spaces: spaces, inbox: inbox, labels: labels)
                Divider()
                VStack(spacing: 0) {
                    ForEach(rows, id: \.roomID) { row in
                        InboxRowView(
                            row: row,
                            networkName: NetworkNames.displayName(of: row.network) ?? row.network,
                            now: Fixture.now,
                            style: style,
                            isSelecting: false,
                            isSelected: row.roomID == "ch-general",
                            isHovered: false,
                            hoverAct: {},
                            accept: {},
                            decline: {}
                        ) { EmptyView() }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 300)
            XCTAssertGreaterThan(size.height, 300)
        }
    }

    func testDirectChat() throws {
        let scenario = try SeedScenario.load("direct")
        let events = try scenario.events(chat: "dm-ann")
        let items = Fixture.items(events, isDirect: true)
        let messages = items.compactMap { if case let .message(message) = $0 { message } else { nil } }
        XCTAssertEqual(messages.count, 17)
        XCTAssertTrue(messages.allSatisfy(\.isDirect))

        let suiteName = "courier.seed-direct.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = ScratchDefaults.suite(named: suiteName)!
        let preferences = ComposerPreferences(defaults: store)
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("courier-seed-direct"),
            environment: [:], launcher: FoundationProcessLauncher()))
        let conversation = ConversationModel(appModel: app, preferences: preferences)
        let directRow = try XCTUnwrap(scenario.inboxRows().first { $0.roomID == "dm-ann" })
        let composer = ComposerModel(sender: SnapshotMessageSender(), draftDelay: 0, sleep: { _ in },
                                     now: { Fixture.now })
        composer.open("dm-ann")
        composer.features = Fixture.features
        composer.network = "whatsapp"
        composer.text = "On my way!"

        let ui = MessageUI()
        let actions = Courier.MessageActions(now: { Fixture.now })
        let recentItems = Array(items.suffix(8))
        let sizes = try Snapshot.render("seed-direct", width: 620) {
            VStack(spacing: 0) {
                ConversationHeader(row: directRow, networkName: "WhatsApp", conversation: conversation)
                Divider()
                VStack(spacing: 0) {
                    ForEach(recentItems) { item in
                        TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
                    }
                }
                .padding(14)
                Divider()
                ComposerView(
                    composer: composer,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight),
                    menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
                )
            }
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 400)
            XCTAssertGreaterThan(size.height, 300)
        }
    }
}
