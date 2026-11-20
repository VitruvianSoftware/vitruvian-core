// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Where a found message says it is ("Kent Hua in Eddie & Kent · Google Chat"), the "Press ⌘F to search in …" line,
/// and when a message's hover bar shows.
@MainActor
final class SearchResultPresentationTests: XCTestCase {
    // MARK: - The line that says where a result is

    func testGroupResultNamesSenderChatAndNetwork() {
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: "Kent Hua", chatTitle: "Eddie & Kent", networkName: "Google Chat",
                                          isDirect: false),
            "Kent Hua in Eddie & Kent · Google Chat")
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: "You", chatTitle: "Eddie & Kent", networkName: "Google Chat",
                                          isDirect: false),
            "You in Eddie & Kent · Google Chat")
    }

    func testOneToOneResultLeavesTheChatOut() {
        // The chat's title would only be the other person's name again.
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: "Kent Hua", chatTitle: "Kent Hua", networkName: "Google Chat",
                                          isDirect: true),
            "Kent Hua · Google Chat")
    }

    func testMissingPartsAreLeftOutNotShownEmpty() {
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: "Kent Hua", chatTitle: "Eddie & Kent", networkName: "", isDirect: false),
            "Kent Hua in Eddie & Kent")
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: "Kent Hua", chatTitle: "", networkName: "Signal", isDirect: false),
            "Kent Hua in Unnamed chat · Signal")
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: "Kent Hua", chatTitle: "Kent Hua", networkName: "", isDirect: true),
            "Kent Hua")
    }

    func testScopedResultOmitsChatAndNetwork() {
        XCTAssertEqual(
            SearchResultLocation.subtitle(
                sender: "Kent Hua",
                chatTitle: "Eddie & Kent",
                networkName: "Google Chat",
                isDirect: false,
                scopedToSingleChat: true
            ),
            "Kent Hua"
        )
        XCTAssertEqual(
            SearchResultLocation.subtitle(
                sender: "You",
                chatTitle: "Kent Hua",
                networkName: "Signal",
                isDirect: true,
                scopedToSingleChat: true
            ),
            "You"
        )
    }

    func testScopeDisplayNameMatchesChatHeader() {
        let model = inbox()
        var row = groupRow("!g", name: "Eddie Stecker, Kent Hua")
        row.network = "gchat"
        model.setSnapshotRowsForTesting([row])
        model.setKnownMembers(
            [
                GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
                GroupTitleMember(userID: "@kent", name: "Kent Hua"),
            ],
            isComplete: true,
            for: "!g"
        )

        XCTAssertEqual(
            SearchScopePresentation.displayName(scopeRoomID: "!g", scopeRow: row, inbox: model),
            "Eddie & Kent"
        )
        XCTAssertEqual(
            SearchScopePresentation.displayName(
                scopeRoomID: "!g",
                scopeRow: row,
                inbox: model,
                openChatRoomID: "!g",
                openChatDisplayTitle: "Eddie & Kent"
            ),
            "Eddie & Kent"
        )

        var unnamed = groupRow("!u", name: "")
        unnamed.memberPreview = []
        XCTAssertEqual(
            SearchScopePresentation.displayName(scopeRoomID: "!u", scopeRow: unnamed, inbox: model),
            "Unnamed chat"
        )
        XCTAssertNil(SearchScopePresentation.displayName(scopeRoomID: nil, scopeRow: nil, inbox: model))
    }

    func testSearchPanelControlsHideAccountsAndCommandsWhenScoped() {
        let global = SearchPanelControls.resolve(
            isScopedToChat: false,
            hasAccounts: true,
            filters: SearchFilterSet(),
            hasCommandBarAction: true
        )
        XCTAssertTrue(global.showsAccountsFilter)
        XCTAssertTrue(global.showsChatTypeFilter)
        XCTAssertTrue(global.showsCommandsChip)

        let scoped = SearchPanelControls.resolve(
            isScopedToChat: true,
            hasAccounts: true,
            filters: SearchFilterSet(networks: ["signal"]),
            hasCommandBarAction: true
        )
        XCTAssertFalse(scoped.showsAccountsFilter)
        XCTAssertFalse(scoped.showsChatTypeFilter)
        XCTAssertFalse(scoped.showsCommandsChip)
    }

    // MARK: - The chat's title: the inbox row's

    private func inbox() -> InboxModel {
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Vitruvian Courier.app/Contents/Helpers/vitruvian-courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/vitruvian-courier-test-search-title"), environment: [:],
            launcher: FakeLauncher { _, _ in })
        let defaults = ScratchDefaults.suite(named: "courier.test.searchtitle.\(UUID().uuidString)")!
        return InboxModel(appModel: AppModel(supervisor: supervisor), preferences: InboxPreferences(defaults: defaults))
    }

    private func groupRow(_ id: String, name: String, localName: String = "") -> InboxRow {
        var row = InboxRow(roomID: id, network: "gchat", name: name, avatarPath: "", isDirect: false, lastTS: 1,
                           preview: "", previewKind: .text, previewMine: false, unread: 0, muted: false)
        row.localName = localName
        row.memberPreview = [RowMember(userID: "@eddie", name: "Eddie Stecker"),
                             RowMember(userID: "@kent", name: "Kent Hua")]
        return row
    }

    private func hit(room: String, roomName: String, direct: Bool = false) -> MessageHit {
        MessageHit(eventID: "$1", roomID: room, roomName: roomName, network: "gchat", isDirect: direct,
                   sender: "@kent", senderName: "Kent Hua", mine: false, ts: 1, seq: 1, snippet: "dinner")
    }

    func testResultNamesItsChatAsTheInboxRowDoes() {
        let inbox = inbox()
        // The bridge names this group by its members; the inbox row shows it as "Eddie & Kent".
        let row = groupRow("!g", name: "Eddie Stecker, Kent Hua")
        inbox.setSnapshotRowsForTesting([row])
        let found = hit(room: "!g", roomName: "Eddie Stecker, Kent Hua")

        XCTAssertEqual(inbox.displayTitle(for: row), "Eddie & Kent")
        XCTAssertEqual(inbox.chatTitle(for: found), inbox.displayTitle(for: row), "one title, from one place")
        XCTAssertNotEqual(inbox.chatTitle(for: found), found.roomName)
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: found.senderLine, chatTitle: inbox.chatTitle(for: found),
                                          networkName: "Google Chat", isDirect: found.isDirect),
            "Kent Hua in Eddie & Kent · Google Chat")
    }

    func testRenamedChatShowsItsCurrentNameNotTheOneTheHitCarries() {
        let inbox = inbox()
        // The hit carries the name the chat had; the chat has since been named "Dinner crew".
        let found = hit(room: "!g", roomName: "Eddie Stecker, Kent Hua")
        inbox.setSnapshotRowsForTesting([groupRow("!g", name: "Eddie Stecker, Kent Hua")])
        XCTAssertEqual(inbox.chatTitle(for: found), "Eddie & Kent")

        inbox.setSnapshotRowsForTesting([groupRow("!g", name: "Dinner crew")])
        XCTAssertEqual(inbox.chatTitle(for: found), "Dinner crew")
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: found.senderLine, chatTitle: inbox.chatTitle(for: found),
                                          networkName: "Google Chat", isDirect: false),
            "Kent Hua in Dinner crew · Google Chat")
    }

    func testAChatOutsideTheListUsesItsFetchedRowThenTheEnginesName() {
        let inbox = inbox()
        let found = hit(room: "!old", roomName: "Eddie Stecker, Kent Hua")
        XCTAssertEqual(inbox.chatTitle(for: found), "Eddie Stecker, Kent Hua", "no row anywhere: the engine's name")
        XCTAssertEqual(inbox.chatTitle(for: found, fetchedRow: groupRow("!old", name: "Eddie Stecker, Kent Hua")),
                       "Eddie & Kent", "a row read for the result titles it the same way")
    }

    func testGroupSubtitleWhenMissingFromInboxUsesFetchedRowAndFallsBackToEngineName() {
        let inbox = inbox()
        let found = hit(room: "!old", roomName: "Eddie Stecker, Kent Hua")
        XCTAssertNil(inbox.row(of: "!old"))

        let fetched = groupRow("!old", name: "Eddie Stecker, Kent Hua")
        XCTAssertEqual(
            SearchResultLocation.subtitle(
                sender: found.senderLine,
                chatTitle: inbox.chatTitle(for: found, fetchedRow: fetched),
                networkName: "Google Chat",
                isDirect: found.isDirect),
            "Kent Hua in Eddie & Kent · Google Chat")

        XCTAssertEqual(
            SearchResultLocation.subtitle(
                sender: found.senderLine,
                chatTitle: inbox.chatTitle(for: found, fetchedRow: nil),
                networkName: "Google Chat",
                isDirect: found.isDirect),
            "Kent Hua in Eddie Stecker, Kent Hua · Google Chat")
    }

    // MARK: - "Press ⌘F to search in …"

    func testOfferSaysTheShortcutAndTheChat() {
        XCTAssertEqual(SearchInChatOffer(roomID: "!g", title: "Eddie & Kent", shortcut: "⌘F").text,
                       "Press ⌘F to search in Eddie & Kent")
        XCTAssertEqual(SearchInChatOffer(roomID: "!g", title: "", shortcut: "⌘F").text,
                       "Press ⌘F to search in this chat")
        XCTAssertEqual(SearchInChatOffer(roomID: "!g", title: "Eddie & Kent", shortcut: nil).text,
                       "Search in Eddie & Kent", "no shortcut to name")
    }

    func testOfferReadsTheShortcutFromTheRegistry() throws {
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: "courier.test.offer.\(UUID().uuidString)"))
        let hotkeys = HotkeyRegistry(defaults: defaults)
        XCTAssertEqual(SearchInChatOffer.make(roomID: "!g", title: "Eddie & Kent", hotkeys: hotkeys)?.shortcut, "⌘F",
                       "Search in Chat's default")
        XCTAssertNil(SearchInChatOffer.make(roomID: nil, title: "x", hotkeys: hotkeys), "no chat open, no line")

        hotkeys.setEnabled(false, for: HotkeyID.searchInChat)
        XCTAssertNil(SearchInChatOffer.make(roomID: "!g", title: "Eddie & Kent", hotkeys: hotkeys)?.shortcut,
                     "a shortcut turned off isn't promised")
    }

    // MARK: - The hover bar

    private func shown(canAct: Bool = true, selected: Bool = true, menu: Bool = false, picking: Bool = false,
                       pointer: ActionBarPointer = ActionBarPointer(), covered: Bool = false) -> Bool {
        ActionBarVisibility.isShown(canAct: canAct, isSelected: selected, menuOpen: menu, pickingReaction: picking,
                                    pointer: pointer, timelineCovered: covered)
    }

    func testBarShowsOnTheSelectedMessageOnly() {
        XCTAssertTrue(shown())
        XCTAssertFalse(shown(selected: false))
        XCTAssertFalse(shown(canAct: false))
    }

    func testBarGoesWhenAPanelCoversTheChat() {
        XCTAssertFalse(shown(covered: true), "the search panel is open")
        XCTAssertFalse(shown(menu: true, covered: true), "even with the message's menu open behind it")
        XCTAssertFalse(shown(picking: true, covered: true))
    }

    func testBarGoesWhenThePointerLeavesAndComesBack() {
        var pointer = ActionBarPointer()
        pointer.rowHover(true)
        XCTAssertTrue(shown(pointer: pointer))

        pointer.rowHover(false)
        XCTAssertTrue(shown(pointer: pointer), "not at once: the pointer may be on its way to the bar")
        pointer.settle()
        XCTAssertFalse(shown(pointer: pointer), "gone from the row and the bar")

        pointer.rowHover(true)
        XCTAssertTrue(shown(pointer: pointer), "back on the message")
    }

    func testPointerCrossingFromTheRowToTheBarKeepsTheBar() {
        var pointer = ActionBarPointer()
        pointer.rowHover(true)
        pointer.rowHover(false)
        pointer.barHover(true)
        pointer.settle()
        XCTAssertTrue(shown(pointer: pointer), "the bar is part of the message")
        pointer.barHover(false)
        pointer.settle()
        XCTAssertFalse(shown(pointer: pointer))
    }

    func testBarStaysForTheMessagesOwnMenuAndReactionPicker() {
        var pointer = ActionBarPointer()
        pointer.rowHover(true)
        pointer.rowHover(false)
        pointer.settle()
        XCTAssertTrue(shown(menu: true, pointer: pointer), "the pointer leaves to reach the menu")
        XCTAssertTrue(shown(picking: true, pointer: pointer))
    }

    func testCoveringTheChatOnlyPausesTheBar() {
        var pointer = ActionBarPointer()
        pointer.rowHover(true)
        XCTAssertFalse(shown(pointer: pointer, covered: true), "a panel or sheet is over the chat")
        XCTAssertTrue(shown(pointer: pointer, covered: false),
                      "it closed with the pointer still over the message: the bar is back, no re-entry needed")

        // A pointer that left while covered is gone when the cover lifts.
        pointer.rowHover(false)
        pointer.settle()
        XCTAssertFalse(shown(pointer: pointer, covered: true))
        XCTAssertFalse(shown(pointer: pointer, covered: false))
    }

    func testKeyboardSelectionShowsTheBarWithoutAPointer() {
        var pointer = ActionBarPointer()
        XCTAssertTrue(shown(pointer: pointer), "nothing has left: the pointer was never there")
        pointer.rowHover(true)
        pointer.rowHover(false)
        pointer.settle()
        XCTAssertFalse(shown(pointer: pointer))
        pointer.selectionChanged()
        XCTAssertTrue(shown(pointer: pointer), "selected again with the arrow keys")
    }
}
