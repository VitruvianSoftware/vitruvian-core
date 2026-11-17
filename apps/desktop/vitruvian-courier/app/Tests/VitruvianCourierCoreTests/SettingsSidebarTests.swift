// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class SettingsSidebarTests: XCTestCase {
    private func account(
        _ network: String,
        state: AccountState = .connected,
        logins: [Login] = []
    ) -> Account {
        Account(network: network, displayName: network.capitalized, flows: [], state: state, logins: logins)
    }

    // MARK: Sidebar rows

    func testEveryPaneHasARowWithASymbolAndATitleInPaneOrder() {
        XCTAssertEqual(SettingsSidebar.items.map(\.pane), SettingsPaneID.allCases)
        for item in SettingsSidebar.items {
            XCTAssertFalse(item.symbolName.isEmpty, "\(item.pane) needs a symbol")
            XCTAssertFalse(item.title.isEmpty, "\(item.pane) needs a title")
            XCTAssertEqual(item.id, item.pane.id)
        }
    }

    func testEveryRowHasItsOwnTileColour() {
        let colours = SettingsSidebar.items.map(\.tile)
        XCTAssertEqual(Set(colours).count, colours.count, "two rows share a colour: \(colours)")
    }

    // MARK: Account card

    func testConnectedCountCountsEachLoginAndSkipsAccountsThatAreNotConnected() {
        let accounts = [
            account("whatsapp", logins: [
                Login(accountID: "a", state: .connected),
                Login(accountID: "b", state: .connected),
                Login(accountID: "c", state: .badCredentials),
            ]),
            account("signal"),  // no list of logins: counts itself
            account("slack", state: .badCredentials),
            account("telegram", state: .notStarted),
        ]
        XCTAssertEqual(SettingsAccountCard.connectedCount(of: accounts), 3)
        XCTAssertEqual(SettingsAccountCard.connectedCount(of: []), 0)
    }

    func testCardSaysHowManyAccountsAreConnectedAndWhichPlan() {
        let ten = (0 ..< 10).map { account("net\($0)") }
        let many = SettingsAccountCard.make(accounts: ten)
        XCTAssertEqual(many.connectedCount, 10)
        XCTAssertEqual(many.title, "10 accounts")
        XCTAssertEqual(many.subtitle, "Vitruvian Courier Plan")

        XCTAssertEqual(SettingsAccountCard.make(accounts: [account("signal")]).title, "1 account")
        XCTAssertEqual(SettingsAccountCard.make(accounts: []).title, "No accounts")
    }

    // MARK: Control tint

    func testSettingsControlsKeepAVividThemeAccentAndReplaceAGreyOne() {
        for preset in CourierThemePreset.allCases {
            let tint = SettingsControlTint.hex(forThemeAccent: preset.defaultAccentHex)
            if preset == .slate {
                XCTAssertEqual(tint, SettingsControlTint.fallbackHex, "Slate is nearly grey: 'on' would look like 'off'")
            } else {
                XCTAssertEqual(tint, preset.defaultAccentHex, "\(preset) is a clear colour")
            }
        }
        XCTAssertEqual(SettingsControlTint.hex(forThemeAccent: "#888888"), SettingsControlTint.fallbackHex)
        XCTAssertEqual(SettingsControlTint.hex(forThemeAccent: "not a colour"), SettingsControlTint.fallbackHex)
    }

    // MARK: "Delay notifications for" footnote

    /// The footnote may only say what the code does. The code behind each claim is tested where it lives:
    /// `NotificationCoordinatorTests.testDelayBatchingHoldsNormalMessageCancelsOnReadAndDeliversWhenUnread` (held, then
    /// dropped when the chat is read) and `testOTPMessageBypassesDelayAndAutoCopiesOnlyWhenEnabledEvenInMutedChat`
    /// (a code skips the wait). It must not promise that a burst becomes one notification: each message is sent alone.
    func testDelayFootnoteMakesOnlyClaimsTheCodeKeeps() {
        let text = NotificationPreferences.delayFootnote
        XCTAssertTrue(text.contains("read the chat"))
        XCTAssertTrue(text.contains("verification code"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("burst"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("one notification"))
    }

    func testAMessageWithACodeSkipsTheDelayAndAPlainOneKeepsIt() throws {
        let suiteName = "settings-sidebar-delay-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = NotificationPreferences(defaults: defaults)
        prefs.delaySeconds = 60

        let room = InboxRow(
            roomID: "!a", network: "whatsapp", name: "Chat A", avatarPath: "", isDirect: true, lastTS: 0, preview: "",
            previewKind: .text, previewMine: false, unread: 0, muted: false, archived: false, lowPriority: false,
            hidden: false, markedUnread: false, request: false, mutedBy: .none, mutedByName: "")
        let context = NotificationPolicy.Context(
            me: Timeline.meUserID, connectedAt: 1_000_000, now: 1_030_000, openRoomID: nil, isLooking: false,
            requestNotifications: true)
        func delay(for text: String) -> Int {
            let event = Event(
                eventID: "$1", roomID: "!a", sender: "@other:courier.local", senderName: "Sam", mine: false,
                type: "m.room.message", content: .object(["msgtype": .string("m.text"), "body": .string(text)]),
                ts: 1_020_000, seq: 1, status: .sent)
            return NotificationPolicy.evaluate(event: event, room: room, context: context, preferences: prefs)
                .delaySeconds
        }
        XCTAssertEqual(delay(for: "Your verification code is 123456"), 0)
        XCTAssertEqual(delay(for: "Dinner at 7?"), 60)
    }
}
