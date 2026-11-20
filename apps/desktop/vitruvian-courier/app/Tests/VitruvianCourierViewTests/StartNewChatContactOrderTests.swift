// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// New Chat's Contacts list with bare phone numbers mixed in: named people first, the numbers after under "Other
/// numbers", and a number already listed under a name left out. Look at start-new-chat-numbers-*.
@MainActor
final class StartNewChatContactOrderTests: XCTestCase {
    private func contact(_ name: String, _ network: String, _ account: String, _ identifiers: [String] = []) -> ContactCandidate {
        ContactCandidate(
            userID: "@\(name.filter(\.isLetter))\(identifiers.first ?? ""):courier.local",
            name: name,
            network: network,
            accountID: account,
            identifiers: identifiers
        )
    }

    private var accounts: [Account] {
        [
            Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .connected),
            Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .connected),
        ]
    }

    private var candidates: [ContactCandidate] {
        [
            contact("+12134476502", "whatsapp", "wa-1"),
            contact("(+1 213) 555-0111 (WA)", "whatsapp", "wa-1"),
            contact("+12134476599", "whatsapp", "wa-1"),
            contact("Zara Example", "whatsapp", "wa-1", ["+1 213-555-0111"]),
            contact("Room 101", "signal", "sig-1"),
            contact("Adam Example", "signal", "sig-1", ["+12134476502"]),
        ]
    }

    func testNamedContactsListFirstAndDuplicateNumbersAreLeftOut() {
        let sorted = StartNewChatPresentation.sortedContacts(candidates, filter: nil)
        XCTAssertEqual(sorted.map(\.name), ["Adam Example", "Room 101", "Zara Example", "+12134476599"])
    }

    func testTheKeyboardWalksNamedThenNumbers() {
        let draft = StartNewChatDraft(accounts: accounts, candidates: candidates)
        let sorted = StartNewChatPresentation.sortedContacts(candidates, filter: nil)
        XCTAssertEqual(
            StartNewChatPresentation.navigableRowIDs(draft: draft, recentRows: []),
            sorted.map { "contact:\($0.id)" }
        )
        let last = sorted.last
        XCTAssertEqual(
            StartNewChatPresentation.candidate(forRowID: "contact:\(last?.id ?? "")", draft: draft, recentRows: []),
            last
        )
    }

    func testAnAccountFilterOnlyHidesANumberBehindAPersonWhoIsAlsoShown() {
        // Adam (Signal) has +12134476502. Filtered to WhatsApp, Adam is not shown, so his WhatsApp number stays.
        let wa = StartNewChatPresentation.sortedContacts(candidates, filter: "whatsapp")
        XCTAssertEqual(wa.map(\.name), ["Zara Example", "+12134476502", "+12134476599"])
    }

    func testListRendersWithNumbersAfterNames() throws {
        let draft = StartNewChatDraft(accounts: accounts, candidates: candidates)
        let sizes = try Snapshot.render("start-new-chat-numbers", width: 520, height: 520) {
            StartNewChatView(draft: draft)
        }
        XCTAssertEqual(sizes.count, 2)
    }

    func testMultiNetworkPersonListsOnceAndExpandsToEndpointSubRows() throws {
        let waAlice = contact("Alice Example", "whatsapp", "wa-1", ["+1 213-447-6502"])
        let sigAlice = contact("Alice Example", "signal", "sig-1", ["(213) 447-6502"])
        let sam1 = contact("Sam", "whatsapp", "wa-1", ["+1 555-010-0001"])
        let sam2 = contact("Sam", "signal", "sig-1", ["+1 555-010-0002"])

        let grouped = StartNewChatPresentation.contactPersonSections(
            [waAlice, sigAlice, sam1, sam2],
            accounts: accounts,
            filter: nil
        )
        XCTAssertEqual(grouped.named.count, 3, "Alice merges across WhatsApp and Signal; two Sams stay distinct")
        let aliceGroup = try XCTUnwrap(grouped.named.first)
        XCTAssertTrue(aliceGroup.isMultiNetwork)
        XCTAssertEqual(aliceGroup.networks, ["whatsapp", "signal"])

        let draft = StartNewChatDraft(accounts: accounts, candidates: [waAlice, sigAlice, sam1, sam2])
        let parentRowID = "contact:\(aliceGroup.id)"
        let collapsedIDs = StartNewChatPresentation.navigableRowIDs(draft: draft, recentRows: [])
        XCTAssertEqual(collapsedIDs.count, 3)
        XCTAssertEqual(collapsedIDs.first, parentRowID)
        XCTAssertEqual(
            StartNewChatPresentation.confirmAction(draft: draft, recentRows: [], selectedRowID: parentRowID),
            .toggleExpand(parentRowID)
        )

        let expandedIDs = StartNewChatPresentation.navigableRowIDs(
            draft: draft,
            recentRows: [],
            expandedRowIDs: [parentRowID]
        )
        let expectedSubIDs = aliceGroup.endpoints.map {
            StartNewChatPresentation.subRowID(parentRowID: parentRowID, endpoint: $0)
        }
        XCTAssertEqual(expandedIDs.count, 5)
        XCTAssertEqual(Array(expandedIDs[1 ... 2]), expectedSubIDs)
        XCTAssertEqual(
            StartNewChatPresentation.confirmAction(
                draft: draft,
                recentRows: [],
                selectedRowID: expectedSubIDs[1],
                expandedRowIDs: [parentRowID]
            ),
            .openDirectChat(sigAlice)
        )
    }

    func testMultiNetworkExpandedAndOverflowingChipsSnapshot() throws {
        let waAlice = contact("Alice Example", "whatsapp", "wa-1", ["+1 213-447-6502"])
        let sigAlice = contact("Alice Example", "signal", "sig-1", ["(213) 447-6502"])
        let tgAlice = contact("Alice Example", "telegram", "tg-1", ["+12134476502"])
        let extraAccounts = accounts + [
            Account(network: "telegram", displayName: "Telegram", flows: ["qr"], state: .connected),
            Account(network: "slack", displayName: "Slack", flows: ["oauth"], state: .connected),
            Account(network: "discord", displayName: "Discord", flows: ["qr"], state: .connected),
            Account(network: "instagram", displayName: "Instagram", flows: ["cookie"], state: .connected),
            Account(network: "gchat", displayName: "Google Chat", flows: ["google"], state: .connected),
        ]
        let list = [waAlice, sigAlice, tgAlice, contact("Bob Example", "slack", "sl-1", ["bob@example.com"])]
        let aliceGroup = try XCTUnwrap(
            StartNewChatPresentation.contactPersonSections(list, accounts: extraAccounts, filter: nil).named.first
        )
        let draft = StartNewChatDraft(accounts: extraAccounts, candidates: list)
        let sizes = try Snapshot.render("start-new-chat-multinetwork", width: 520, height: 520) {
            StartNewChatView(
                draft: draft,
                initialExpandedRowIDs: ["contact:\(aliceGroup.id)"]
            )
        }
        XCTAssertEqual(sizes.count, 2)
    }
}
