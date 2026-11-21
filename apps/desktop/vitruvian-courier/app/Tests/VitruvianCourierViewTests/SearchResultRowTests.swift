// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// How a search result reads: the matched words in bold on a soft tint (the engine's ranges, so matching is the
/// search's own: case and accents ignored), where the message is, and the panel's pieces drawn light and dark for a
/// person to look at (search-panel-*, search-chips-*).
@MainActor
final class SearchResultRowTests: XCTestCase {
    private func hit(_ snippet: String, ranges: [(Int, Int)], isDirect: Bool = false, mine: Bool = false,
                     name: String = "Kent Hua", room: String = "Eddie Stecker, Kent Hua") -> MessageHit {
        MessageHit(eventID: "$\(snippet.hashValue)", roomID: "!g", roomName: room, network: "gchat",
                   isDirect: isDirect, sender: "@kent", senderName: name, mine: mine, ts: Fixture.millis(3), seq: 1,
                   snippet: snippet, ranges: ranges.map { TextRange(start: $0.0, length: $0.1) })
    }

    /// The words that are bold and on the tint, in order.
    private func marked(_ text: AttributedString) -> [String] {
        text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
    }

    func testEveryMatchGetsTheTintAndStaysBold() {
        // The engine matched "dinner" in "Dinner" (case) and "jose" in "José" (accent): ranges are of what is there.
        let found = hit("Dinner with José, then dinner again", ranges: [(0, 6), (12, 4), (23, 6)])
        let text = SearchRowText.snippet(of: found)
        XCTAssertEqual(marked(text), ["Dinner", "José", "dinner"])
        let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(text[$0.range].characters) }
        XCTAssertEqual(bold, ["Dinner", "José", "dinner"], "bold is kept")
        XCTAssertEqual(String(text.characters), found.snippet, "the words themselves are untouched")
    }

    func testAMatchInAnAccentWrittenAsTwoCodePointsIsWholeAndAnEmojiDoesNotShiftIt() {
        // "José" with a combining accent is 5 UTF-16 units; 🎉 is 2: ranges count units, not Characters.
        let found = hit("🎉 Ask Jose\u{301} soon", ranges: [(7, 5)])
        let text = SearchRowText.snippet(of: found)
        XCTAssertEqual(marked(text), ["Jose\u{301}"])
    }

    func testHighlightOffsetWithEmojiMultiScalarEmojiAndCombiningMarkBeforeMatch() {
        let singleEmoji = MessageHit(
            eventID: "$emoji-single", roomID: "!g", roomName: "Eddie Stecker, Kent Hua", network: "gchat",
            isDirect: false, sender: "@kent", senderName: "Kent Hua", mine: false, ts: Fixture.millis(3), seq: 1,
            snippet: "😀 hello world", ranges: [TextRange(start: 3, length: 5)])
        let singleText = SearchRowText.snippet(of: singleEmoji)
        XCTAssertEqual(marked(singleText), ["hello"])
        let singleUntinted = singleText.runs.filter { $0.backgroundColor == nil }
            .map { String(singleText[$0.range].characters) }
        XCTAssertEqual(singleUntinted, ["😀 ", " world"])

        // "👨‍👩‍👧‍👦" is 11 UTF-16 units (7 scalars, 1 Character) and "e\u{301}" is 2 UTF-16 units (1 Character).
        let multiScalar = MessageHit(
            eventID: "$emoji-zwj", roomID: "!g", roomName: "Eddie Stecker, Kent Hua", network: "gchat",
            isDirect: false, sender: "@kent", senderName: "Kent Hua", mine: false, ts: Fixture.millis(3), seq: 1,
            snippet: "👨‍👩‍👧‍👦 cafe\u{301} hello world", ranges: [TextRange(start: 18, length: 5)])
        let multiText = SearchRowText.snippet(of: multiScalar)
        XCTAssertEqual(marked(multiText), ["hello"])
        let multiUntinted = multiText.runs.filter { $0.backgroundColor == nil }
            .map { String(multiText[$0.range].characters) }
        XCTAssertEqual(multiUntinted, ["👨‍👩‍👧‍👦 cafe\u{301} ", " world"])
    }

    func testTextWithNoMatchHasNoTintAndAStaleRangeIsLeftOut() {
        XCTAssertEqual(marked(SearchRowText.snippet(of: hit("a picnic", ranges: []))), [])
        XCTAssertEqual(marked(SearchRowText.snippet(of: hit("a picnic", ranges: [(2, 6), (40, 3)]))), ["picnic"])
    }

    func testTintIsASoftYellowThatIsNotFullStrength() throws {
        let tint = NSColor(SearchRowText.matchTint)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            var alpha: CGFloat = 1
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                alpha = tint.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1
            }
            XCTAssertLessThan(alpha, 0.6, "low opacity, so the words stay readable in \(name.rawValue)")
            XCTAssertGreaterThan(alpha, 0.1, "and still visible")
        }
    }

    func testLocationLineMakesTheSenderStrongAndTheRestSecondary() {
        let line = "Kent Hua in Eddie & Kent · Google Chat"
        let text = SearchRowText.location(sender: "Kent Hua", line: line)
        XCTAssertEqual(String(text.characters), line)
        let strong = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(text[$0.range].characters) }
        XCTAssertEqual(strong, ["Kent Hua"])
        // A line that doesn't start with the sender (it can't, today) is plain secondary text rather than a crash.
        XCTAssertTrue(SearchRowText.location(sender: "Someone", line: line).runs.allSatisfy {
            $0.inlinePresentationIntent == nil
        })
    }

    // MARK: - Pictures

    private func offlineApp() -> AppModel {
        AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-snapshots"),
            environment: [:], launcher: FoundationProcessLauncher()))
    }

    func testPanelPiecesDrawnLightAndDark() throws {
        let name = "courier.searchrows.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let app = offlineApp()
        let search = SearchModel(appModel: app, recents: RecentSearches(defaults: defaults), open: { _ in })
        search.filters.sender = "others"

        let group = hit("Are we still on for dinner on Saturday?", ranges: [(20, 6)])
        let direct = hit("Dinner is on me, José", ranges: [(0, 6), (17, 4)], isDirect: true, room: "Kent Hua")
        let mine = hit("I booked dinner", ranges: [(9, 6)], mine: true)
        let offer = SearchInChatOffer(roomID: "!g", title: "Eddie & Kent", shortcut: "⌘F")

        let sizes = try Snapshot.render("search-panel-rows", width: 640) {
            VStack(alignment: .leading, spacing: 0) {
                SearchFilterBar(search: search, accounts: [])
                    .padding(.horizontal, 14).padding(.bottom, 10)
                Divider()
                Text(verbatim: offer.text).font(.callout).foregroundStyle(.secondary).padding(10)
                HStack {
                    Text(String(localized: "Messages"))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Spacer()
                    Button(String(localized: "Show partial matches")) {}
                        .buttonStyle(.routineLink).font(.caption)
                }
                .padding(.horizontal, 16)
                ForEach([group, direct, mine], id: \.eventID) { found in
                    SearchRowView(item: .message(found), isSelected: found.eventID == group.eventID,
                                  networkName: { _ in "Google Chat" },
                                  chatTitle: { _ in found.isDirect ? "Kent Hua" : "Eddie & Kent" })
                }
                Text(SearchPanel.onThisMacFooter)
                    .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 16).padding(.top, 4)
            }
            .padding(.vertical, 8)
            .courierSurface(.searchPanel(cornerRadius: 12))
            .padding(20)
            .background(Color.blue.opacity(0.5))
        }
        XCTAssertEqual(sizes.count, 2)
    }

    func testScopedPanelUsesHeaderNameHidesAccountsAndCommandsAndOmitsChatLocation() throws {
        let name = "courier.searchrows.scoped.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let app = offlineApp()
        app.setAccountsForTesting([
            Account(network: "gchat", displayName: "Google Chat", flows: ["google"], state: .connected),
            Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .connected),
        ])
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: defaults))
        var row = Fixture.row("!g", "Eddie Stecker, Kent Hua", network: "gchat", direct: false, ts: 5, preview: "Dinner?")
        row.memberPreview = [
            RowMember(userID: "@eddie", name: "Eddie Stecker"),
            RowMember(userID: "@kent", name: "Kent Hua"),
        ]
        inbox.setSnapshotRowsForTesting([row])
        inbox.setKnownMembers(
            [
                GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
                GroupTitleMember(userID: "@kent", name: "Kent Hua"),
            ],
            isComplete: true,
            for: "!g"
        )

        let search = SearchModel(appModel: app, recents: RecentSearches(defaults: defaults), open: { _ in })
        search.show(in: "!g")
        XCTAssertTrue(search.isScoped)
        XCTAssertTrue(search.isScopedToSingleChat)

        let resolvedScope = SearchScopePresentation.displayName(
            scopeRoomID: search.scopeRoomID,
            scopeRow: search.scope,
            inbox: inbox,
            openChatRoomID: "!g",
            openChatDisplayTitle: "Eddie & Kent"
        )
        XCTAssertEqual(resolvedScope, "Eddie & Kent")

        let controls = SearchPanelControls.resolve(
            isScopedToChat: search.isScoped,
            hasAccounts: !inbox.linkedNetworks.isEmpty,
            filters: search.filters,
            hasCommandBarAction: true
        )
        XCTAssertFalse(controls.showsAccountsFilter)
        XCTAssertFalse(controls.showsCommandsChip)

        let groupHit = hit("Dinner with Eddie?", ranges: [(0, 6)])
        let expectedTime = SearchDate.text(forMillis: groupHit.ts)
        XCTAssertEqual(
            MediaCell(hit: groupHit, chatTitle: "Eddie & Kent", isSelected: false, scopedToSingleChat: true).helpText(),
            "Kent Hua · \(expectedTime)"
        )
        XCTAssertEqual(
            SearchResultLocation.subtitle(
                sender: "Kent Hua",
                chatTitle: "Eddie & Kent",
                networkName: "Google Chat",
                isDirect: false,
                scopedToSingleChat: search.isScopedToSingleChat
            ),
            "Kent Hua"
        )

        let sizes = try Snapshot.render("search-panel-scoped", width: 680) {
            VStack(alignment: .leading, spacing: 8) {
                SearchPanel(
                    search: search,
                    inbox: inbox,
                    maxHeight: 260,
                    openChatRoomID: "!g",
                    openChatDisplayTitle: "Eddie & Kent",
                    onOpenCommandBar: { _ in }
                )
                SearchRowView(
                    item: .message(groupHit),
                    isSelected: true,
                    networkName: { _ in "Google Chat" },
                    chatTitle: { _ in "Eddie & Kent" },
                    scopedToSingleChat: search.isScopedToSingleChat
                )
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        XCTAssertEqual(sizes.count, 2)
    }
}
